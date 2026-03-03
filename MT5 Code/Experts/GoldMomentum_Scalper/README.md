# Gold Momentum Scalper

**Asset:** XAU/USD · **Timeframe:** M5

- **50 EMA** for trend: price above = bullish bias, below = bearish.
- **Stochastic 14,3,3:** long when %K crosses above %D in oversold (both < 20); short when %K crosses below %D in overbought (both > 80).
- **Entry:** at the open of the M5 candle that follows the signal candle close.
- **SL:** 7–10 pips beyond the signal candle (below low / above high); if that would be >15 pips, use a fixed 10 pips from entry.
- **TP:** fixed 15–20 pips or minimum 1:1.5 R:R.

Attach to XAU/USD M5. Set `InpPipsPerPoint` (often 10) to match your broker.
