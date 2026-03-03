//+------------------------------------------------------------------+
//|                                                    AMIS.mq5      |
//| Adaptive Microstructure-Informed Scalper                        |
//| For BTCUSD & XAUUSD - AWBVM, HMFMRC, MARM                       |
//+------------------------------------------------------------------+
#property copyright "AMIS Strategy"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| MQL5 series access (no iClose/iOpen in MQL5 - use Copy* )        |
//+------------------------------------------------------------------+
double GetPriceClose(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if (CopyClose(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}
double GetPriceOpen(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if (CopyOpen(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}
double GetPriceHigh(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if (CopyHigh(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}
double GetPriceLow(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if (CopyLow(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}
long GetVolumeReal(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   long arr[];
   ArraySetAsSeries(arr, true);
   if (CopyRealVolume(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}
datetime GetBarTime(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   datetime arr[];
   ArraySetAsSeries(arr, true);
   if (CopyTime(sym, tf, shift, 1, arr) < 1) return 0;
   return arr[0];
}

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_AMIS_REGIME
{
   REGIME_IMPULSIVE_BREAKOUT = 0,  // Impulsive Breakout
   REGIME_TREND_UP           = 1,  // Trending Up
   REGIME_TREND_DOWN         = 2,  // Trending Down
   REGIME_QUIET_ACCUMULATION = 3,  // Quiet Accumulation
   REGIME_CHOPPY             = 4,  // Choppy / Ranging
   REGIME_UNKNOWN            = 5   // Unknown
};

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== AWBVM (Aggressor-Weighted Bar Volume Momentum) ==="
input int    InpAWBVM_Lookback            = 3;       // AWBVM lookback (M1 bars)
input double InpAWBVM_Activation_Mult     = 1.0;     // AWBVM activation vs avg volume
input int    InpAWBVM_AvgVolumeBars       = 20;      // Bars for average M1 volume

input group "=== VWMA & Trend (M1) ==="
input int    InpShort_VWMA_Period         = 9;       // Short VWMA period (M1)
input int    InpLong_VWMA_Period          = 21;      // Long VWMA period (M1)

input group "=== ATR & Volatility ==="
input int    InpATR_Period_M1             = 14;      // ATR period M1
input int    InpATR_Period_M5             = 14;      // ATR period M5
input int    InpEMA_Period_M5             = 50;      // EMA period M5 (trend proxy)
input int    InpATR_SMA_Period_M5         = 100;     // SMA period for volatility ratio (M5)

input group "=== HMFMRC (Regime) ==="
input int    InpM5_VWMA_Chop_Lookback     = 20;      // M5 bars for chop (VWMA crosses)
input int    InpM5_Short_VWMA             = 9;       // M5 Short VWMA
input int    InpM5_Long_VWMA              = 21;      // M5 Long VWMA
input double InpVolatilityRatioHigh       = 1.2;     // Vol ratio above = high vol
input double InpVolatilityRatioLow        = 0.7;     // Vol ratio below = low vol
input int    InpChopCrossThreshold        = 6;       // Crosses above = choppy

input group "=== MARM (Microstructure-Aware Risk) ==="
input int    InpSpread_Lookback_M1        = 10;      // Spread lookback (bars)
input double InpMaxSpreadMultiplier       = 1.5;     // Max spread vs avg (filter)
input double InpSL_ATR_Mult_M1            = 1.5;     // Stop loss (ATR M1 mult)
input double InpTP_ATR_Mult_M1            = 2.0;     // Take profit (ATR M1 mult)
input double InpRegimeSLMult_Impulsive    = 1.2;     // SL mult in Impulsive regime
input double InpRegimeSLMult_Quiet        = 1.8;     // SL mult in Quiet regime
input double InpRiskPercent               = 0.5;     // Risk per trade (% of equity)
input double InpMaxLotSize                = 0.5;     // Max lot size
input double InpMinLotSize                = 0.01;    // Min lot size

input group "=== Trade ==="
input int    InpMagicNumber               = 202503;  // Magic number
input int    InpMaxSpreadPoints           = 50;      // Max spread (points) hard cap
input bool   InpTradeBTCUSD               = true;    // Allow BTCUSD
input bool   InpTradeXAUUSD               = true;    // Allow XAUUSD
input bool   InpSkipChoppyQuietRegimes    = false;   // Skip entries in Choppy/Quiet

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
double         g_spreadBuffer[];  // rolling spread for average (we store last N)
int            g_spreadBufferSize = 0;
datetime       g_lastBarTimeM1    = 0;
datetime       g_lastBarTimeM5    = 0;

//+------------------------------------------------------------------+
//| VWMA - Volume-Weighted Moving Average (calculated from series)   |
//+------------------------------------------------------------------+
double GetVWMA(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double sumPV = 0, sumV = 0;
   for (int i = shift; i < shift + period && i < 500; i++)
   {
      double c = GetPriceClose(sym, tf, i);
      long   v = GetVolumeReal(sym, tf, i);
      if (v <= 0) v = 1;
      sumPV += c * (double)v;
      sumV  += (double)v;
   }
   if (sumV <= 0) return 0;
   return sumPV / sumV;
}

//+------------------------------------------------------------------+
//| AWBVM - Aggressor-Weighted Bar Volume Momentum                   |
//| Returns score and fills avgVolume with average M1 real volume    |
//+------------------------------------------------------------------+
double GetAWBVM(const string sym, int lookback, int avgVolumeBars, double &avgVolume)
{
   avgVolume = 0;
   for (int k = 1; k <= avgVolumeBars; k++)
      avgVolume += (double)GetVolumeReal(sym, PERIOD_M1, k);
   if (avgVolumeBars > 0) avgVolume /= (double)avgVolumeBars;

   double score = 0;
   // Use only closed bars (shift 1 = last closed) to avoid repainting
   for (int iBar = 1; iBar <= lookback; iBar++)
   {
      double o = GetPriceOpen(sym, PERIOD_M1, iBar);
      double c = GetPriceClose(sym, PERIOD_M1, iBar);
      double h = GetPriceHigh(sym, PERIOD_M1, iBar);
      double l = GetPriceLow(sym, PERIOD_M1, iBar);

      int directionalFactor = (c > o) ? 1 : -1;
      double barRange = h - l;
      double relativeCloseStrength = (barRange > 0.0000001) ?
         MathAbs(c - o) / barRange : 0.0;

      long vol = GetVolumeReal(sym, PERIOD_M1, iBar);
      if (vol <= 0) vol = 1;
      double barAggression = (double)vol * relativeCloseStrength * (double)directionalFactor;
      score += barAggression;
   }
   return score;
}

//+------------------------------------------------------------------+
//| Average spread (MARM) - we use a rolling buffer updated on bar   |
//+------------------------------------------------------------------+
double GetAverageSpread(int lookback)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) point = _Point;
   double currentSpread = (point > 0) ? (ask - bid) / point : 0;

   if (ArraySize(g_spreadBuffer) < lookback)
      ArrayResize(g_spreadBuffer, lookback);

   for (int i = lookback - 1; i > 0; i--)
      g_spreadBuffer[i] = g_spreadBuffer[i-1];
   g_spreadBuffer[0] = currentSpread;
   g_spreadBufferSize = MathMin(g_spreadBufferSize + 1, lookback);

   double sum = 0;
   int    cnt = MathMin(g_spreadBufferSize, lookback);
   for (int j = 0; j < cnt; j++)
      sum += g_spreadBuffer[j];
   return (cnt > 0) ? sum / (double)cnt : currentSpread;
}

//+------------------------------------------------------------------+
//| HMFMRC - Volatility Range Position (M5): ATR / SMA(100) of close |
//+------------------------------------------------------------------+
double GetVolatilityRangePositionM5(const string sym, int atrPeriod, int smaPeriod)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(sym, PERIOD_M5, atrPeriod);
   if (atrHandle == INVALID_HANDLE) return 0;
   if (CopyBuffer(atrHandle, 0, 0, 3, atr) < 2) { IndicatorRelease(atrHandle); return 0; }
   double currentATR = atr[1];
   IndicatorRelease(atrHandle);

   double sma[];
   ArraySetAsSeries(sma, true);
   int smaHandle = iMA(sym, PERIOD_M5, smaPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if (smaHandle == INVALID_HANDLE) return 0;
   if (CopyBuffer(smaHandle, 0, 0, 3, sma) < 2) { IndicatorRelease(smaHandle); return 0; }
   double currentSMA = sma[1];
   IndicatorRelease(smaHandle);

   if (currentSMA <= 0) return 0;
   return currentATR / currentSMA;
}

//+------------------------------------------------------------------+
//| HMFMRC - Count VWMA crosses on M5 over lookback bars              |
//+------------------------------------------------------------------+
int GetM5_VWMA_ChopScore(const string sym, int lookback, int shortPer, int longPer)
{
   int crosses = 0;
   double prevShort = GetVWMA(sym, PERIOD_M5, shortPer, 1);
   double prevLong  = GetVWMA(sym, PERIOD_M5, longPer,  1);
   for (int b = 0; b < lookback - 1; b++)
   {
      double s = GetVWMA(sym, PERIOD_M5, shortPer, b + 1);
      double l = GetVWMA(sym, PERIOD_M5, longPer,  b + 1);
      if ((prevShort > prevLong && s < l) || (prevShort < prevLong && s > l))
         crosses++;
      prevShort = s;
      prevLong  = l;
   }
   return crosses;
}

//+------------------------------------------------------------------+
//| EMA slope proxy (M5) - positive = uptrend, negative = downtrend   |
//+------------------------------------------------------------------+
double GetEMASlopeM5(const string sym, int emaPeriod)
{
   double ema[];
   ArraySetAsSeries(ema, true);
   int h = iMA(sym, PERIOD_M5, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (h == INVALID_HANDLE) return 0;
   if (CopyBuffer(h, 0, 0, 5, ema) < 4) { IndicatorRelease(h); return 0; }
   double slope = ema[1] - ema[3];
   IndicatorRelease(h);
   return slope;
}

//+------------------------------------------------------------------+
//| HMFMRC - Classify micro-regime                                   |
//+------------------------------------------------------------------+
ENUM_AMIS_REGIME ClassifyRegime(const string sym,
                                double volRatio,
                                int chopScore,
                                double emaSlope,
                                double atrM5)
{
   bool highVol = (volRatio >= InpVolatilityRatioHigh);
   bool lowVol  = (volRatio <= InpVolatilityRatioLow);
   bool choppy  = (chopScore >= InpChopCrossThreshold);
   bool strongUp   = (emaSlope > atrM5 * 0.3);
   bool strongDown = (emaSlope < -atrM5 * 0.3);

   if (highVol && strongUp && !choppy) return REGIME_IMPULSIVE_BREAKOUT;
   if (highVol && strongDown && !choppy) return REGIME_IMPULSIVE_BREAKOUT;
   if (strongUp && !choppy)  return REGIME_TREND_UP;
   if (strongDown && !choppy) return REGIME_TREND_DOWN;
   if (lowVol && choppy)      return REGIME_QUIET_ACCUMULATION;
   if (choppy)                return REGIME_CHOPPY;
   return REGIME_UNKNOWN;
}

//+------------------------------------------------------------------+
//| MARM - Regime-based SL multiplier                               |
//+------------------------------------------------------------------+
double GetRegimeSLMultiplier(ENUM_AMIS_REGIME regime)
{
   switch (regime)
   {
      case REGIME_IMPULSIVE_BREAKOUT: return InpRegimeSLMult_Impulsive;
      case REGIME_QUIET_ACCUMULATION:
      case REGIME_CHOPPY:             return InpRegimeSLMult_Quiet;
      default:                        return 1.0;
   }
}

//+------------------------------------------------------------------+
//| ATR M1 value at shift 1 (last closed bar)                        |
//+------------------------------------------------------------------+
double GetATR_M1(const string sym, int period, int shift = 1)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int h = iATR(sym, PERIOD_M1, period);
   if (h == INVALID_HANDLE) return 0;
   if (CopyBuffer(h, 0, shift, 2, atr) < 2) { IndicatorRelease(h); return 0; }
   double v = atr[0];
   IndicatorRelease(h);
   return v;
}

//+------------------------------------------------------------------+
//| Lot size from risk % and SL distance                             |
//+------------------------------------------------------------------+
double CalcLotSize(double slPoints, double riskPercent)
{
   if (slPoints <= 0) return InpMinLotSize;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPercent / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (tickVal <= 0 || tickSize <= 0 || point <= 0) return InpMinLotSize;
   double valuePerPointPerLot = tickVal * (point / tickSize);
   if (valuePerPointPerLot <= 0) return InpMinLotSize;
   double lots = riskAmount / (slPoints * valuePerPointPerLot);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(maxL, lots));
   return MathMax(InpMinLotSize, MathMin(InpMaxLotSize, lots));
}

//+------------------------------------------------------------------+
//| Check if new M1 bar                                              |
//+------------------------------------------------------------------+
bool IsNewBarM1()
{
   datetime t = GetBarTime(_Symbol, PERIOD_M1, 0);
   if (t != g_lastBarTimeM1) { g_lastBarTimeM1 = t; return true; }
   return false;
}

bool IsNewBarM5()
{
   datetime t = GetBarTime(_Symbol, PERIOD_M5, 0);
   if (t != g_lastBarTimeM5) { g_lastBarTimeM5 = t; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Symbol allowed (BTCUSD / XAUUSD)                                 |
//+------------------------------------------------------------------+
bool IsSymbolAllowed()
{
   string s = _Symbol;
   if (StringFind(s, "BTC") >= 0 && InpTradeBTCUSD) return true;
   if (StringFind(s, "XAU") >= 0 && InpTradeXAUUSD) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if (!IsSymbolAllowed())
   {
      Print("AMIS: Symbol ", _Symbol, " not in allowed list (BTCUSD/XAUUSD).");
      return INIT_SUCCEEDED; // don't trade but don't fail
   }
   if (!g_symbol.Name(_Symbol))
   {
      Print("AMIS: Symbol info failed.");
      return INIT_FAILED;
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if ((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   ArrayResize(g_spreadBuffer, MathMax(InpSpread_Lookback_M1, 10));
   ArrayInitialize(g_spreadBuffer, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!IsSymbolAllowed()) return;
   if (!g_symbol.RefreshRates()) return;

   double avgSpread = GetAverageSpread(InpSpread_Lookback_M1);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) point = _Point;
   double currentSpread = (point > 0) ? (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point : 0;
   if (currentSpread > InpMaxSpreadPoints) return;
   if (avgSpread > 0 && currentSpread > avgSpread * InpMaxSpreadMultiplier) return;

   bool newM1 = IsNewBarM1();
   bool newM5 = IsNewBarM5();

   // Regime on M5 (recompute on M5 bar for efficiency)
   double volRatio = GetVolatilityRangePositionM5(_Symbol, InpATR_Period_M5, InpATR_SMA_Period_M5);
   int chopScore = GetM5_VWMA_ChopScore(_Symbol, InpM5_VWMA_Chop_Lookback, InpM5_Short_VWMA, InpM5_Long_VWMA);
   double emaSlope = GetEMASlopeM5(_Symbol, InpEMA_Period_M5);
   double atrM5Val = 0;
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(_Symbol, PERIOD_M5, InpATR_Period_M5);
      if (h != INVALID_HANDLE && CopyBuffer(h, 0, 1, 2, buf) >= 2) atrM5Val = buf[0];
      if (h != INVALID_HANDLE) IndicatorRelease(h);
   }
   ENUM_AMIS_REGIME regime = ClassifyRegime(_Symbol, volRatio, chopScore, emaSlope, atrM5Val);

   // AWBVM on M1 (on new M1 bar use last closed bar for signal)
   double avgVolM1 = 0;
   double awbvmScore = GetAWBVM(_Symbol, InpAWBVM_Lookback, InpAWBVM_AvgVolumeBars, avgVolM1);
   double threshold = avgVolM1 * InpAWBVM_Activation_Mult;
   if (avgVolM1 <= 0) return;  // no volume data, skip to avoid false signals

   double vwmaShortM1 = GetVWMA(_Symbol, PERIOD_M1, InpShort_VWMA_Period, 1);
   double vwmaLongM1  = GetVWMA(_Symbol, PERIOD_M1, InpLong_VWMA_Period,  1);
   double atrM1 = GetATR_M1(_Symbol, InpATR_Period_M1, 1);
   if (atrM1 <= 0) return;

   double slMult = InpSL_ATR_Mult_M1 * GetRegimeSLMultiplier(regime);
   double slDist = atrM1 * slMult;
   double tpDist = atrM1 * InpTP_ATR_Mult_M1;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) point = _Point;
   double slPoints = (point > 0) ? slDist / point : 0;

   // Only open on new M1 bar to avoid multiple entries per bar
   if (newM1)
   {
      bool skipRegime = InpSkipChoppyQuietRegimes &&
                        (regime == REGIME_CHOPPY || regime == REGIME_QUIET_ACCUMULATION);
      bool bullish = !skipRegime && (vwmaShortM1 > vwmaLongM1) && (awbvmScore > threshold);
      bool bearish = !skipRegime && (vwmaShortM1 < vwmaLongM1) && (awbvmScore < -threshold);

      if (bullish && CountPositions(POSITION_TYPE_BUY) == 0 && slPoints > 0)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double sl = NormalizeDouble(ask - slDist, digits);
         double tp = NormalizeDouble(ask + tpDist, digits);
         double lots = CalcLotSize(slPoints, InpRiskPercent);
         if (lots >= InpMinLotSize && g_trade.Buy(lots, _Symbol, ask, sl, tp, "AMIS"))
            Print("AMIS BUY lots=", lots, " regime=", EnumToString(regime));
      }
      else if (bearish && CountPositions(POSITION_TYPE_SELL) == 0 && slPoints > 0)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double sl = NormalizeDouble(bid + slDist, digits);
         double tp = NormalizeDouble(bid - tpDist, digits);
         double lots = CalcLotSize(slPoints, InpRiskPercent);
         if (lots >= InpMinLotSize && g_trade.Sell(lots, _Symbol, bid, sl, tp, "AMIS"))
            Print("AMIS SELL lots=", lots, " regime=", EnumToString(regime));
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions by type for this magic                            |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_position.SelectByIndex(i)) continue;
      if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagicNumber) continue;
      if (g_position.PositionType() == type) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
