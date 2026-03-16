//+------------------------------------------------------------------+
//| GOLD_Hurst_Regime_Adaptive.mq5                                   |
//| Hurst Exponent Adaptive Regime Scalper for XAUUSD               |
//|                                                                  |
//| Scientific Basis:                                                |
//| - "Improved prediction of global gold prices: An innovative      |
//|    Hurst-reconfiguration-based machine learning approach"        |
//|   IDEAS RePec 2024 - Journal of Resources Policy                 |
//| - "Comparison of Fractal Dimension Algorithms by Hurst Exponent  |
//|    using Gold Price Time Series" - ResearchGate                  |
//|                                                                  |
//| Hurst Exponent Interpretation:                                   |
//|   H > 0.55 → Persistent/Trending market  → MOMENTUM entry       |
//|   H < 0.45 → Anti-persistent/Mean-revert → FADE extremes entry  |
//|   H 0.45-0.55 → Random walk / Noisy      → NO TRADE (skip)      |
//|                                                                  |
//| TREND mode:   EMA cross + ADX > 20 + RSI direction              |
//| RANGE mode:   BB extreme bounce + RSI <35 or >65 + Stoch confirm |
//|                                                                  |
//| Magic: 110002                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"
#include "Gold_Research_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF      = PERIOD_M5;

input group "=== Hurst Exponent ==="
input int    InpHurstBars        = 64;    // Bars for R/S analysis (min 32, ideal 64+)
input double InpHurstTrend       = 0.55;  // Above = trending mode
input double InpHurstRange       = 0.45;  // Below = mean-revert mode

input group "=== Trend Mode (H > threshold) ==="
input int    InpEMAFast          = 8;
input int    InpEMASlow          = 21;
input int    InpADX_Period       = 14;
input double InpADXMinTrend      = 20.0;

input group "=== Range Mode (H < threshold) ==="
input int    InpBB_Period        = 20;
input double InpBB_Dev           = 2.0;
input int    InpRSI_Period       = 14;
input double InpRSIBuyMax        = 35.0;  // RSI below = oversold (buy)
input double InpRSISellMin       = 65.0;  // RSI above = overbought (sell)
input int    InpStochK           = 5;
input int    InpStochD           = 3;
input int    InpStochSlowing     = 3;
input double InpStochBuyMax      = 25.0;
input double InpStochSellMin     = 75.0;

input group "=== Session ==="
input int    InpUTCOffset        = 0;
input bool   InpAllSessions      = true;

input group "=== Risk ==="
input double InpRiskPct_Trend    = 0.5;   // Higher risk in trending regime
input double InpRiskPct_Range    = 0.35;  // Lower risk in mean-revert regime
input double InpSL_ATR_Trend     = 1.0;
input double InpSL_ATR_Range     = 0.8;
input double InpTP_RR_Trend      = 2.0;   // Wider TP on trends
input double InpTP_RR_Range      = 1.2;   // Tighter TP on mean reversion
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 0.5;
input int    InpMaxSpread        = 80;

input group "=== Trade ==="
input int    InpMagic            = 110002;

input group "=== MTF D1 Macro Filter ==="
input bool   InpUseMTF    = true;   // Enable daily trend macro filter
input int    InpMTF_D1Min = 0;      // D1 min score (-1=bear ok, 0=neutral ok, 1=bull only)

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InSession()
{
   if (InpAllSessions) return true;
   return SC_IsLondonSession(InpUTCOffset) || SC_IsNYSession(InpUTCOffset);
}

int OnInit()
{
   if (InpHurstBars < 32)
   {
      Print("GOLD_Hurst_Regime: InpHurstBars must be >= 32");
      return INIT_PARAMETERS_INCORRECT;
   }
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

   double H   = GRM_HurstRS(_Symbol, InpTF, InpHurstBars, 1);
   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   int    digs = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if (atr <= 0) return;

   bool longSig = false, shortSig = false;
   double riskPct = InpRiskPct_Trend;
   double slMult  = InpSL_ATR_Trend;
   double tpRR    = InpTP_RR_Trend;

   if (H >= InpHurstTrend)
   {
      // TREND MODE: EMA cross + ADX + RSI direction
      double emaFast = SC_GetEMA(_Symbol, InpTF, InpEMAFast, 1);
      double emaSlow = SC_GetEMA(_Symbol, InpTF, InpEMASlow, 1);
      double emaFastP= SC_GetEMA(_Symbol, InpTF, InpEMAFast, 2);
      double emaSlowP= SC_GetEMA(_Symbol, InpTF, InpEMASlow, 2);
      double plusDI, minusDI;
      double adx = GRM_GetADXFull(_Symbol, InpTF, InpADX_Period, 1, plusDI, minusDI);
      double rsi = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);

      // Bullish EMA cross: fast crossed above slow, ADX confirming, RSI > 50
      bool emaBullCross = (emaFastP <= emaSlowP && emaFast > emaSlow);
      bool emaBearCross = (emaFastP >= emaSlowP && emaFast < emaSlow);

      longSig  = emaBullCross && adx >= InpADXMinTrend && plusDI > minusDI && rsi > 50;
      shortSig = emaBearCross && adx >= InpADXMinTrend && minusDI > plusDI && rsi < 50;
   }
   else if (H <= InpHurstRange)
   {
      // RANGE / MEAN-REVERSION MODE: BB extreme + RSI + Stoch
      riskPct = InpRiskPct_Range;
      slMult  = InpSL_ATR_Range;
      tpRR    = InpTP_RR_Range;

      double upper, middle, lower;
      SC_GetBB(_Symbol, InpTF, InpBB_Period, InpBB_Dev, 1, upper, middle, lower);
      double rsi = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
      double close = SC_Close(_Symbol, InpTF, 1);
      double k, d;
      SC_GetStoch(_Symbol, InpTF, InpStochK, InpStochD, InpStochSlowing, 1, k, d);

      // Buy at BB lower band: price touches/breaks lower, RSI oversold, Stoch turning up
      longSig  = (close <= lower) && (rsi <= InpRSIBuyMax)  && (k <= InpStochBuyMax)  && (k > d);
      // Sell at BB upper band
      shortSig = (close >= upper) && (rsi >= InpRSISellMin) && (k >= InpStochSellMin) && (k < d);
   }
   // else H in random zone: no trade

   if (longSig)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - atr * slMult, digs);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(ask + slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      riskPct, InpMinLot, InpMaxLot);
         string tag = (H >= InpHurstTrend) ? "Hurst_Trend_L" : "Hurst_Range_L";
         g_trade.Buy(lots, _Symbol, ask, sl, tp, tag);
      }
   }
   else if (shortSig)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + atr * slMult, digs);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(bid - slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      riskPct, InpMinLot, InpMaxLot);
         string tag = (H >= InpHurstTrend) ? "Hurst_Trend_S" : "Hurst_Range_S";
         g_trade.Sell(lots, _Symbol, bid, sl, tp, tag);
      }
   }
}
