# AMIS – Adaptive Microstructure-Informed Scalper

MetaTrader 5 Expert Advisor for **BTCUSD** and **XAUUSD**, implementing the three-pillar AMIS framework:

1. **AWBVM** (Aggressor-Weighted Bar Volume Momentum) – infers directional aggressive order flow on M1.
2. **HMFMRC** (Hybrid Multi-Factor Micro-Regime Classification) – classifies micro-regimes (e.g. Impulsive Breakout, Quiet Accumulation, Choppy) on M5.
3. **MARM** (Microstructure-Aware Adaptive Risk Management) – spread filter, regime-based SL/TP multipliers, and risk-based lot size.

## Timeframes

- **M1**: Entry/exit, AWBVM, VWMA trend, dynamic SL/TP.
- **M5**: Regime detection (volatility ratio, VWMA chop score, EMA slope).

## Installation

1. Copy the `AMIS` folder into `MQL5/Experts/`.
2. Compile `AMIS.mq5` in MetaEditor (F7).
3. Attach the EA to an M1 chart of BTCUSD or XAUUSD.
4. Enable "Allow Algo Trading" and set inputs as needed.

## Main inputs

| Group | Parameter | Description |
|-------|-----------|-------------|
| AWBVM | AWBVM_Lookback | M1 bars for momentum sum (default 3). |
| AWBVM | AWBVM_Activation_Mult | Threshold = avg volume × this (default 1.0). |
| VWMA | Short/Long VWMA | 9/21 on M1 for trend alignment. |
| ATR | ATR_Period_M1 / M5 | 14 for volatility and SL/TP. |
| HMFMRC | VolatilityRatioHigh/Low | M5 ATR/SMA(100) thresholds for high/low vol. |
| HMFMRC | ChopCrossThreshold | M5 VWMA crosses above this = choppy. |
| MARM | MaxSpreadMultiplier | Skip entry if current spread > avg × this. |
| MARM | SL/TP ATR mult | Base 1.5 / 2.0; regime multipliers apply to SL. |
| Trade | TradeBTCUSD / TradeXAUUSD | Which symbols are allowed. |
| Trade | SkipChoppyQuietRegimes | If true, no new entries in Choppy/Quiet regimes. |

## Logic summary

- **Entries** (on new M1 bar only):  
  - **Long**: Short VWMA > Long VWMA (M1) and AWBVM score > activation threshold.  
  - **Short**: Short VWMA < Long VWMA and AWBVM score < −threshold.
- **Spread**: Entry blocked if current spread > `MaxSpreadPoints` or > `AvgSpread × MaxSpreadMultiplier`.
- **SL/TP**: Based on M1 ATR; SL multiplier is increased in Quiet/Choppy and reduced in Impulsive regime.
- **Lots**: From `RiskPercent` of equity and SL distance (MARM).

## Regimes (HMFMRC)

- **Impulsive Breakout**: High volatility, strong EMA slope, low chop.
- **Trend Up/Down**: Strong EMA slope, not choppy.
- **Quiet Accumulation**: Low volatility, high chop.
- **Choppy**: High VWMA cross count.

Adjust `InpVolatilityRatioHigh`, `InpVolatilityRatioLow`, and `InpChopCrossThreshold` to tune regime borders for your broker/symbol.
