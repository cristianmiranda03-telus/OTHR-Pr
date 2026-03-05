# Liquidity Vacuum Scalper

**XAUUSD 1–2 min, NY session (9:30–16:00 EST).**

Detects a **Pulse** (large, high-volume candle) followed by **Discontinuity** (sudden drop in volume and range), then enters in the Pulse direction. Uses ATR volatility filter, dynamic SL (Pulse extreme + buffer), trailing at 1R, TP 1.8–2.2 R, **Counter-Pulse** exit (opposite aggressive candle), and time-based exit (e.g. 10 bars).

- **Pulse:** range ≥ 1.5×ATR(5), volume > 2.5×SMA(vol,20), body > 75% range, opposing wick < 25%.
- **Discontinuity:** volume < 0.5×Pulse volume, range < 40% Pulse range, small body.
- Set **InpTimeframe** to M1 or M2; adjust **InpATR_EMAPeriod** (60 for M1, 30 for M2).
