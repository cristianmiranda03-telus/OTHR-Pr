# Trading Framework with AI — Design & Modular Agents

## Overview

This framework provides **modular n8n workflows** that you can run independently or together for trading-related automation:

1. **Data sources**: Binance (trades, ticker, klines), Finnhub (economic calendar).
2. **AI layer**: FuelXI (e.g. `gemini-2.5-pro`) for summaries, sentiment, and digest generation.
3. **Notifications**: Telegram (via Bot API) for alerts and digests.

All components use **HTTP/API** only (no proprietary node logic beyond n8n’s HTTP Request and Code nodes), so you can swap APIs (e.g. another LLM or calendar provider) by changing URLs and payloads.

---

## Modular Agents

### 1. Binance agent (market data)

- **Role**: Fetch public market data (no API key required for spot market data).
- **Endpoints used**:
  - `GET /api/v3/trades?symbol=BTCUSDT&limit=N` — recent trades.
  - `GET /api/v3/ticker/24hr?symbol=BTCUSDT` — 24h ticker.
  - `GET /api/v3/ticker/24hr` — all 24h tickers (for multi-pair digest).
  - `GET /api/v3/klines?symbol=BTCUSDT&interval=1h&limit=24` — OHLCV candles.
- **Used in**: 01, 02, 04, 05.

### 2. Economic calendar agent

- **Role**: Fetch events that can move markets (stocks, forex, crypto sentiment).
- **API**: Finnhub `GET /api/v1/calendar/economic?from=&to=&token=`.
- **Filtering**: High-impact events only (e.g. by `impact` or `importance`) before sending to Telegram or AI.
- **Used in**: 03, 05.

### 3. AI agent (FuelXI)

- **Role**: Summarize data, infer short-term sentiment, and produce a short digest.
- **API**: `POST https://api.fuelix.ai/v1/chat/completions` with `Authorization: Bearer <key>`.
- **Model**: e.g. `gemini-2.5-pro` (adjust in each workflow if you use another model).
- **Used in**: 02, 04, 05.

### 4. Telegram agent

- **Role**: Send formatted messages (and optional media) to a chat/channel.
- **API**: `POST https://api.telegram.org/bot<token>/sendMessage` (JSON body: `chat_id`, `text`, `parse_mode`, etc.).
- **Used in**: All workflows that notify (01–05).

---

## Workflow Matrix

| Workflow | Trigger | Binance | Calendar | AI | Telegram |
|----------|---------|---------|----------|----|----------|
| 01_binance_btc_trades_telegram | 2 min | Trades | — | — | ✓ |
| 02_binance_trades_ai_telegram | 5 min | Trades + Ticker | — | ✓ | ✓ |
| 03_economic_calendar_telegram | 6 h | — | ✓ | — | ✓ |
| 04_ai_trend_sentiment | 1 h | Ticker + Klines | — | ✓ | ✓ |
| 05_combined_trading_signals | 4 h | Tickers (all) | ✓ | ✓ | ✓ |

---

## Credentials and env vars

Use **n8n credentials** where possible; otherwise set environment variables and reference them in nodes as `$env.VAR_NAME`.

| Variable / Credential | Purpose |
|------------------------|--------|
| `TELEGRAM_BOT_TOKEN` | Telegram Bot API token from @BotFather. |
| `TELEGRAM_CHAT_ID` | Chat or channel ID (e.g. from @RawDataBot or Telegram API). |
| `FUELXI_API_KEY` | FuelXI API key for chat completions. |
| `FINNHUB_API_KEY` | Finnhub API key for economic calendar (free tier available). |

Placeholders in workflows (e.g. `YOUR_BOT_TOKEN`, `YOUR_CHAT_ID`) are fallbacks when env vars are not set; replace them or set env so no secrets are committed.

---

## Extending the framework

- **More pairs**: Duplicate Binance HTTP nodes or add a loop over symbols; adjust the Code node to format multiple pairs.
- **More calendars**: Add another HTTP Request to a second provider (e.g. FXStreet, Trading Economics) and merge results in a Code node before Telegram or AI.
- **Different AI**: Replace FuelXI URL and headers with another OpenAI-compatible or custom chat API; keep the same message shape (system + user with JSON context).
- **Webhooks**: Add a Webhook trigger node to run a workflow on external events (e.g. exchange webhooks, alerting tools) and reuse the same Telegram/AI agents.

---

## Execution order

Workflows are independent. Recommended order for activation:

1. **01** — Fast trade feed (optional; can be noisy).
2. **03** — Economic calendar (low frequency).
3. **04** — Hourly trend/sentiment.
4. **02** — 5‑minute AI summary (optional).
5. **05** — 4‑hour combined digest.

Adjust schedule triggers (cron/interval) in each workflow to match your timezone and rate limits.
