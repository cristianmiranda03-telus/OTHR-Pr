# n8n Trading Framework with AI

Modular automation framework for trading: Binance, economic calendar, AI analysis (FuelXI), and Telegram notifications.

## Structure

```
N8N/
├── README.md                 # This file
├── workflows/                # n8n workflow JSON files (import in n8n)
│   ├── 01_binance_btc_trades_telegram.json
│   ├── 02_binance_trades_ai_telegram.json
│   ├── 03_economic_calendar_telegram.json
│   ├── 04_ai_trend_sentiment.json
│   └── 05_combined_trading_signals.json
├── docs/
│   └── FRAMEWORK.md          # Framework design & modular agents
└── credentials.example.env  # Template for API keys (do not commit real keys)
```

## Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|--------|
| **01** | Schedule (e.g. every 1–5 min) | Binance BTC recent trades → Telegram |
| **02** | Schedule | Binance trades + AI (FuelXI) summary → Telegram |
| **03** | Schedule (daily / pre-market) | Economic calendar (high-impact events) → Telegram |
| **04** | Schedule | Price + volume + AI trend/sentiment → Telegram |
| **05** | Schedule | Combined: trades + calendar + AI → single digest to Telegram |

## Setup

1. **Import workflows** in n8n: Editor → Import from File → select each JSON from `workflows/`.
2. **Credentials** (in n8n or env):
   - **Binance**: no key needed for public market data (trades, ticker).
   - **Telegram**: Bot token from [@BotFather](https://t.me/BotFather); set Chat ID (group/channel).
   - **FuelXI (AI)**: API key from [FuelXI](https://fuelix.ai); used in HTTP Request nodes.
   - **Economic calendar**: e.g. Finnhub API key (free tier) or Trading Economics.
3. **Replace placeholders** in each workflow:
   - `YOUR_TELEGRAM_BOT_TOKEN`, `YOUR_CHAT_ID`
   - `YOUR_FUELXI_API_KEY` (or use n8n credentials)
   - Finnhub/calendar API key where used
4. **Activate** workflows after testing (Execute workflow / Run once).

## APIs Used

- **Binance**: `GET https://api.binance.com/api/v3/trades?symbol=BTCUSDT&limit=20`
- **Telegram**: `https://api.telegram.org/bot<token>/sendMessage`
- **FuelXI**: `https://api.fuelix.ai/v1/chat/completions` (model: e.g. `gemini-2.5-pro`)
- **Economic calendar**: Finnhub `/calendar/economic` or similar (see workflow 03)

## Security

- Do not commit real API keys. Use n8n credentials or environment variables.
- Prefer read-only keys and least privilege for trading APIs.

## License

Use at your own risk. Not financial advice.
