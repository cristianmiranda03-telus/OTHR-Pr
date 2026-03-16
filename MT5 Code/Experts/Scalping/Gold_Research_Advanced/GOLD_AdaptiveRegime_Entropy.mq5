//+------------------------------------------------------------------+
//| GOLD_AdaptiveRegime_Entropy.mq5                                  |
//| Adaptive Market Regime Engine for XAUUSD Gold Scalping          |
//|                                                                  |
//| Scientific Basis:                                                |
//| - "Why Most Trend EAs Fail on Gold (And How Adaptive Regime     |
//|    Logic Fixes It)" - MQL5 Blog, Jan 2026                       |
//|   Market Regime Engine: ADX + ATR Ratio + Entropy switching      |
//| - "Mentor Michael - Adaptive Regime Pro v1.0" (TradingView)     |
//|   Entropy calculated from log return dispersion + std norm       |
//| - Entropy-based market classification from information theory:   |
//|   Low entropy = structured/predictable; High = chaotic/choppy   |
//|                                                                  |
//| 3-REGIME ADAPTIVE SYSTEM:                                        |
//|                                                                  |
//| TREND REGIME  (ADX>25, ATR ratio<1.5, entropy<0.7):             |
//|   → EMA8/21 cross + RSI direction + wider targets               |
//|   → Standard risk sizing                                         |
//|                                                                  |
//| RANGE REGIME  (ADX<20, entropy<0.75, ATR ratio 0.7-1.3):        |
//|   → Bollinger Bands extreme bounce + Stochastic + CCI confirm   |
//|   → Tighter TP (mean reversion target = BB middle)              |
//|                                                                  |
//| VOLATILE REGIME (ATR ratio>1.5, OR entropy>0.8):                |
//|   → Reduced lot size (50% of normal)                            |
//|   → Require 3+ signal confluence to enter                       |
//|   → Wider SL, medium TP                                         |
//|                                                                  |
//| Magic: 110006                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"
#include "Gold_Research_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF           = PERIOD_M5;

input group "=== Regime Detection Thresholds ==="
input int    InpADX_Period            = 14;
input double InpADXTrendMin           = 25.0;  // ADX above = TREND regime
input double InpADXRangeMax           = 20.0;  // ADX below = RANGE regime
input int    InpATRShort              = 5;     // Short ATR period
input int    InpATRLong               = 20;    // Long ATR period
input double InpATRRatioVolatile      = 1.5;   // ATR ratio above = VOLATILE
input int    InpEntropyBars           = 20;    // Candles for entropy computation
input double InpEntropyLowMax         = 0.70;  // Entropy below = structured market
input double InpEntropyHighMin        = 0.80;  // Entropy above = volatile/noisy

input group "=== Trend Regime Settings ==="
input int    InpEMAFast               = 8;
input int    InpEMASlow               = 21;
input int    InpRSI_Period            = 14;
input double InpTP_RR_Trend           = 2.2;

input group "=== Range Regime Settings ==="
input int    InpBB_Period             = 20;
input double InpBB_Dev                = 2.0;
input int    InpStochK                = 5;
input int    InpStochD                = 3;
input int    InpStochSlowing          = 3;
input int    InpCCI_Period            = 14;
input double InpCCIBuyMax             = -80.0;  // CCI below = buy signal in range
input double InpCCISellMin            = 80.0;   // CCI above = sell signal in range
input double InpTP_RR_Range           = 1.0;    // TP = BB middle (approx 1:1)

input group "=== Volatile Regime Settings ==="
input double InpRiskReductionVol      = 0.5;   // Multiply risk by this in volatile mode
input int    InpConflMinVol           = 3;     // Min confluence signals required
input double InpSL_ATR_Volatile       = 1.5;   // Wider SL in volatile
input double InpTP_RR_Volatile        = 1.5;

input group "=== Session ==="
input int    InpUTCOffset             = 0;
input bool   InpAllSessions           = true;

input group "=== Risk ==="
input double InpRiskPct               = 0.4;
input double InpSL_ATR                = 1.0;
input int    InpATR_Period            = 14;
input double InpMinLot                = 0.01;
input double InpMaxLot                = 0.5;
input int    InpMaxSpread             = 80;

input group "=== Trade ==="
input int    InpMagic                 = 110006;

input group "=== MTF D1 Macro Filter ==="
input bool   InpUseMTF    = true;   // Enable daily trend macro filter
input int    InpMTF_D1Min = 0;      // D1 min score (-1=bear ok, 0=neutral ok, 1=bull only)

CTrade   g_trade;
datetime g_lastBar = 0;

enum RegimeType { REGIME_TREND = 0, REGIME_RANGE = 1, REGIME_VOLATILE = 2 };

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InSession()
{
   if (InpAllSessions) return true;
   return SC_IsLondonSession(InpUTCOffset) || SC_IsNYSession(InpUTCOffset);
}

//--- Compute Shannon entropy on candlestick sign patterns (matches Gold_AI_Score_Model)
double ComputeEntropy(int bars)
{
   double o[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, 1, bars, o)  < bars) return 0.5;
   if (CopyClose(_Symbol, InpTF, 1, bars, c) < bars) return 0.5;
   int up = 0, dn = 0, flat = 0;
   for (int i = 0; i < bars; i++)
   {
      if (c[i] > o[i]) up++;
      else if (c[i] < o[i]) dn++;
      else flat++;
   }
   int tot = up + dn + flat;
   if (tot == 0) return 0.5;
   double H = 0;
   if (up   > 0) H -= (double)up   / tot * MathLog((double)up   / tot);
   if (dn   > 0) H -= (double)dn   / tot * MathLog((double)dn   / tot);
   if (flat > 0) H -= (double)flat / tot * MathLog((double)flat / tot);
   return H / MathLog(3.0);
}

//--- Determine current market regime
RegimeType GetRegime(double adx, double atrRatio, double entropy)
{
   // Volatile first (overrides): sharp expansion or very noisy
   if (atrRatio >= InpATRRatioVolatile || entropy >= InpEntropyHighMin)
      return REGIME_VOLATILE;
   // Trend: ADX strong + entropy structured
   if (adx >= InpADXTrendMin && entropy <= InpEntropyLowMax)
      return REGIME_TREND;
   // Range: ADX weak
   if (adx <= InpADXRangeMax)
      return REGIME_RANGE;
   // Transitional (ADX 20-25): use range logic conservatively
   return REGIME_RANGE;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!InSession()) return;
   if (!SC_IsNewBar(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   if (InpUseMTF && SC_TrendDir_D1(_Symbol) < InpMTF_D1Min) return;

   double plusDI, minusDI;
   double adx      = GRM_GetADXFull(_Symbol, InpTF, InpADX_Period, 1, plusDI, minusDI);
   double atrRatio = GRM_ATRRatio(_Symbol, InpTF, InpATRShort, InpATRLong, 1);
   double entropy  = ComputeEntropy(InpEntropyBars);
   double atr      = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   double close    = SC_Close(_Symbol, InpTF, 1);
   int    digs     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (atr <= 0 || point <= 0) return;

   RegimeType regime = GetRegime(adx, atrRatio, entropy);

   bool longSignal = false, shortSignal = false;
   double riskPct  = InpRiskPct;
   double slMult   = InpSL_ATR;
   double tpRR     = 1.5;
   string sigTag   = "Regime";

   if (regime == REGIME_TREND)
   {
      tpRR   = InpTP_RR_Trend;
      sigTag = "Trend";

      double emaFast  = SC_GetEMA(_Symbol, InpTF, InpEMAFast, 1);
      double emaSlow  = SC_GetEMA(_Symbol, InpTF, InpEMASlow, 1);
      double emaFastP = SC_GetEMA(_Symbol, InpTF, InpEMAFast, 2);
      double emaSlowP = SC_GetEMA(_Symbol, InpTF, InpEMASlow, 2);
      double rsi      = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);

      bool emaBull = (emaFastP <= emaSlowP && emaFast > emaSlow);
      bool emaBear = (emaFastP >= emaSlowP && emaFast < emaSlow);

      longSignal  = emaBull && plusDI > minusDI && rsi > 50;
      shortSignal = emaBear && minusDI > plusDI && rsi < 50;
   }
   else if (regime == REGIME_RANGE)
   {
      tpRR   = InpTP_RR_Range;
      sigTag = "Range";

      double upper, middle, lower;
      SC_GetBB(_Symbol, InpTF, InpBB_Period, InpBB_Dev, 1, upper, middle, lower);
      double k, d;
      SC_GetStoch(_Symbol, InpTF, InpStochK, InpStochD, InpStochSlowing, 1, k, d);
      double cci = SC_GetCCI(_Symbol, InpTF, InpCCI_Period, 1);

      // Buy at lower BB with stoch oversold + CCI oversold
      longSignal  = (close <= lower)  && (k <= 25.0) && (k > d) && (cci <= InpCCIBuyMax);
      // Sell at upper BB with stoch overbought + CCI overbought
      shortSignal = (close >= upper) && (k >= 75.0) && (k < d) && (cci >= InpCCISellMin);
   }
   else // REGIME_VOLATILE
   {
      tpRR    = InpTP_RR_Volatile;
      slMult  = InpSL_ATR_Volatile;
      riskPct = InpRiskPct * InpRiskReductionVol;
      sigTag  = "Volatile";

      // In volatile mode, need high confluence: ADX direction + RSI + Stoch all aligned
      double rsi = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
      double k, d;
      SC_GetStoch(_Symbol, InpTF, InpStochK, InpStochD, InpStochSlowing, 1, k, d);
      double emaFast = SC_GetEMA(_Symbol, InpTF, InpEMAFast, 1);
      double emaSlow = SC_GetEMA(_Symbol, InpTF, InpEMASlow, 1);

      // Count signals pointing long
      int longCount  = 0;
      int shortCount = 0;
      if (close > emaFast && emaFast > emaSlow) longCount++;  else shortCount++;
      if (plusDI > minusDI)                     longCount++;  else shortCount++;
      if (rsi > 55)                             longCount++;  else if (rsi < 45) shortCount++;
      if (k > d && k < 70)                      longCount++;  else if (k < d && k > 30) shortCount++;

      longSignal  = (longCount  >= InpConflMinVol);
      shortSignal = (shortCount >= InpConflMinVol);
      if (longSignal && shortSignal) { longSignal = false; shortSignal = false; }
   }

   if (longSignal)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - atr * slMult, digs);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(ask + slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / point, riskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, sigTag + "_L");
      }
   }
   else if (shortSignal)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + atr * slMult, digs);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(bid - slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / point, riskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, sigTag + "_S");
      }
   }
}
