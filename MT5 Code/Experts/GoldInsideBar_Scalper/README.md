# XAU/USD M5 Inside Bar Breakout Scalper

**Asset:** XAU/USD · **Timeframe:** M5

- **SMA 20** as trend filter: Mother and Inside bar must close on the same side (above for long, below for short).
- **Inside Bar:** current candle fully inside the previous (Mother) candle’s high–low range.
- **Long:** next candle closes above Mother bar high → buy at close/open of next bar. **Short:** next candle closes below Mother bar low → sell.
- **SL:** just below Mother bar low (long) or above Mother bar high (short), plus a small buffer in points (e.g. 10–20 for XAU).
- **TP:** entry ± (Mother bar range × 1.5) for ~1:1.5 R:R.

Attach to XAU/USD M5. Tune `InpSL_BufferPoints` to your broker’s point value.
