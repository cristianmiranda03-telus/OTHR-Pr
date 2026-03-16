//+------------------------------------------------------------------+
//| GOLD_VolumeImbalance_DeltaScalp.mq5                              |
//| Volume Delta / Order Flow Imbalance Scalper for XAUUSD          |
//|                                                                  |
//| Scientific Basis:                                                |
//| - "Order Flow for Gold Signals: Footprint, Delta & Imbalance"   |
//|   FXPremiere 2025 - Microstructure gold trading                 |
//| - "Order Flow Imbalance Scalping" - traders.mba                 |
//|   Identifying short-term shifts in buying/selling pressure       |
//| - "XAUUSD Ultimate Sniper v6.0 [Order Flow & Macro]"            |
//|   TradingView - Order flow with macro DXY/yield correlation     |
//|                                                                  |
//| Strategy Logic:                                                  |
//| 1. Compute per-bar volume delta (bullish or bearish volume)      |
//| 2. Count consecutive directional delta streak                    |
//| 3. Compute cumulative delta over N bars → pressure direction     |
//| 4. Volume imbalance ratio > threshold = strong conviction        |
//| 5. EMA50 trend filter + volume spike confirmation               |
//| 6. Entry: 3+ consecutive bull/bear delta bars + price alignment  |
//|                                                                  |
//| Works in any session (London, NY, Asian consolidation)          |
//| Adaptive to both low and high volatility via ATR sizing         |
//|                                                                  |
//| Magic: 110004                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"
#include "Gold_Research_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF          = PERIOD_M5;

input group "=== Volume Delta Parameters ==="
input int    InpStreakMin            = 3;    // Min consecutive same-direction delta bars
input int    InpStreakMax            = 8;    // Max streak (avoid exhaustion)
input int    InpCumDeltaBars         = 8;    // Bars for cumulative delta
input double InpImbalanceRatioMin    = 0.62; // Min bull/bear ratio (0.5=equal, 1=all bull)
input int    InpVolLookback          = 20;   // Bars for average volume reference

input group "=== Volume Spike Filter ==="
input double InpVolSpikeMultiplier   = 1.3;  // Current vol must be > X * avg vol
input bool   InpRequireVolSpike      = true; // Require volume spike for entry

input group "=== Trend Filter ==="
input int    InpEMA_Period           = 50;   // EMA for trend direction filter
input int    InpRSI_Period           = 14;
input double InpRSI_Long_Min         = 40.0; // RSI floor for long entries
input double InpRSI_Short_Max        = 60.0; // RSI ceiling for short entries

input group "=== Session ==="
input int    InpUTCOffset            = 0;
input bool   InpAllSessions          = true;

input group "=== Risk ==="
input double InpRiskPct              = 0.4;
input double InpSL_ATR               = 1.0;
input double InpTP_RR                = 1.6;
input int    InpATR_Period           = 14;
input double InpMinLot               = 0.01;
input double InpMaxLot               = 0.5;
input int    InpMaxSpread            = 80;

input group "=== Trade ==="
input int    InpMagic                = 110004;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min score magnitude to take directional trade (1-3)

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

   int mtfScore = InpUseMTF ? SC_MTF_Score(_Symbol) : 0;

   // Volume delta analysis
   int  streak     = GRM_DeltaStreak(_Symbol, InpTF, InpStreakMax + 2, 1);
   double cumDelta = GRM_CumDelta(_Symbol, InpTF, InpCumDeltaBars, 1);
   double bullRatio = GRM_VolumeImbalanceRatio(_Symbol, InpTF, InpCumDeltaBars, 1);
   double bearRatio = 1.0 - bullRatio;

   // Volume spike check
   bool volSpike = true;
   if (InpRequireVolSpike)
   {
      double avgVol = SC_AvgVolume(_Symbol, InpTF, InpVolLookback, 1);
      double curVol = (double)SC_Volume(_Symbol, InpTF, 1);
      volSpike = (avgVol > 0 && curVol >= avgVol * InpVolSpikeMultiplier);
   }

   // Streak qualification
   bool bullStreak = (streak >= InpStreakMin && streak <= InpStreakMax);
   bool bearStreak = (-streak >= InpStreakMin && -streak <= InpStreakMax);

   // Trend and momentum filters
   double ema   = SC_GetEMA(_Symbol, InpTF, InpEMA_Period, 1);
   double close = SC_Close(_Symbol, InpTF, 1);
   double rsi   = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   int    digs  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (atr <= 0 || point <= 0) return;

   // Long signal: bull streak + high bull imbalance + price above EMA + RSI ok + vol spike
   bool longSignal  = bullStreak
                    && cumDelta > 0
                    && bullRatio >= InpImbalanceRatioMin
                    && close > ema
                    && rsi >= InpRSI_Long_Min
                    && volSpike
                    && (mtfScore >= -InpMTF_MinScore);

   // Short signal: bear streak + high bear imbalance + price below EMA + RSI ok + vol spike
   bool shortSignal = bearStreak
                    && cumDelta < 0
                    && bearRatio >= InpImbalanceRatioMin
                    && close < ema
                    && rsi <= InpRSI_Short_Max
                    && volSpike
                    && (mtfScore <= InpMTF_MinScore);

   if (longSignal)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - atr * InpSL_ATR, digs);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(ask + slD * InpTP_RR, digs);
         double lots = SC_CalcLotSize(slD / point, InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp,
                     StringFormat("VolDelta_L_s%d", streak));
      }
   }
   else if (shortSignal)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + atr * InpSL_ATR, digs);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(bid - slD * InpTP_RR, digs);
         double lots = SC_CalcLotSize(slD / point, InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp,
                      StringFormat("VolDelta_S_s%d", -streak));
      }
   }
}
