//+------------------------------------------------------------------+
//| GOLD_RSI_Hidden_Divergence.mq5                                   |
//| RSI Hidden + Regular Divergence Scalper for XAUUSD              |
//|                                                                  |
//| Scientific Basis:                                                |
//| - "Advanced Gold Scalping Strategy with RSI Divergence"          |
//|   TradingView: atakhadivi - divergence on 1M XAUUSD             |
//| - SMC+XGBoost paper (Sept 2025): RSI as key feature in 85.4%    |
//|   win-rate model alongside Order Blocks and Fair Value Gaps      |
//|                                                                  |
//| Divergence Types Implemented:                                    |
//|   HIDDEN BULLISH:   Price Higher Low + RSI Lower Low  → BUY     |
//|   (continuation - strongest in trending markets)                |
//|   HIDDEN BEARISH:   Price Lower High + RSI Higher High → SELL   |
//|   (continuation - strongest in trending markets)                |
//|   REGULAR BULLISH:  Price Lower Low + RSI Higher Low  → BUY rev |
//|   (reversal - strongest at key support levels)                   |
//|   REGULAR BEARISH:  Price Higher High + RSI Lower High → SELL   |
//|   (reversal - strongest at key resistance levels)                |
//|                                                                  |
//| Confirmation: EMA200 trend alignment + ATR volatility filter     |
//| Any session, low + high volatility                               |
//|                                                                  |
//| Magic: 110003                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"
#include "Gold_Research_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF         = PERIOD_M5;

input group "=== RSI Divergence ==="
input int    InpRSI_Period          = 14;
input int    InpRecentLookback      = 6;   // Bars to find recent pivot
input int    InpPriorLookback       = 20;  // Bars to find prior pivot
input double InpMinRSIDiff          = 3.0; // Min RSI difference between pivots

input group "=== Signal Selection ==="
input bool   InpUseHiddenBull       = true;  // Hidden bullish div (trend continuation)
input bool   InpUseHiddenBear       = true;  // Hidden bearish div (trend continuation)
input bool   InpUseRegularBull      = true;  // Regular bullish div (reversal)
input bool   InpUseRegularBear      = true;  // Regular bearish div (reversal)

input group "=== Confirmation Filters ==="
input int    InpEMA200_Period       = 200;   // Trend filter: hidden div aligned with EMA200
input bool   InpRequireEMAFilter    = true;  // Require price on correct side of EMA200
input int    InpMinATR_Points       = 30;    // Min ATR in points (avoid dead markets)
input double InpMaxATR_Points       = 500;   // Max ATR (avoid extreme news spikes)

input group "=== Session ==="
input int    InpUTCOffset           = 0;
input bool   InpAllSessions         = true;

input group "=== Risk ==="
input double InpRiskPct_Hidden      = 0.5;  // Hidden div = higher confidence
input double InpRiskPct_Regular     = 0.35; // Regular div = moderate confidence
input double InpSL_ATR              = 1.0;
input double InpTP_RR_Hidden        = 2.0;
input double InpTP_RR_Regular       = 1.5;
input int    InpATR_Period          = 14;
input double InpMinLot              = 0.01;
input double InpMaxLot              = 0.5;
input int    InpMaxSpread           = 80;

input group "=== Trade ==="
input int    InpMagic               = 110003;

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

   double atr  = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digs  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (atr <= 0 || point <= 0) return;

   double atrPoints = atr / point;
   if (atrPoints < InpMinATR_Points || atrPoints > InpMaxATR_Points) return;

   double close = SC_Close(_Symbol, InpTF, 1);
   double ema200 = InpRequireEMAFilter
                 ? SC_GetEMA(_Symbol, InpTF, InpEMA200_Period, 1)
                 : 0;

   // Detect all divergence types
   bool hiddenBull = InpUseHiddenBull &&
                     GRM_HiddenBullDiv(_Symbol, InpTF,
                                       InpRecentLookback, InpPriorLookback,
                                       InpRSI_Period, InpMinRSIDiff);

   bool hiddenBear = InpUseHiddenBear &&
                     GRM_HiddenBearDiv(_Symbol, InpTF,
                                       InpRecentLookback, InpPriorLookback,
                                       InpRSI_Period, InpMinRSIDiff);

   bool regBull    = InpUseRegularBull &&
                     GRM_RegularBullDiv(_Symbol, InpTF,
                                        InpRecentLookback, InpPriorLookback,
                                        InpRSI_Period, InpMinRSIDiff);

   bool regBear    = InpUseRegularBear &&
                     GRM_RegularBearDiv(_Symbol, InpTF,
                                        InpRecentLookback, InpPriorLookback,
                                        InpRSI_Period, InpMinRSIDiff);

   // EMA200 filter: hidden div should align with HTF trend
   if (InpRequireEMAFilter && ema200 > 0)
   {
      bool aboveEMA = (close > ema200);
      bool belowEMA = (close < ema200);
      // Hidden bull continuation: only if price is above EMA (uptrend continuation)
      if (!aboveEMA) hiddenBull = false;
      // Hidden bear continuation: only if price is below EMA (downtrend continuation)
      if (!belowEMA) hiddenBear = false;
      // Regular reversals: buy only below EMA (bouncing from oversold to range), sell above
      if (!belowEMA) regBull = false;
      if (!aboveEMA) regBear = false;
   }

   // Priority: hidden div signals (continuation) > regular (reversal)
   bool longSignal  = (hiddenBull || regBull)  && (mtfScore >= -InpMTF_MinScore);
   bool shortSignal = (hiddenBear || regBear)  && (mtfScore <= InpMTF_MinScore);

   if (longSignal && shortSignal) { longSignal = false; shortSignal = false; } // conflict

   bool  isHidden  = longSignal ? hiddenBull : hiddenBear;
   double riskPct  = isHidden ? InpRiskPct_Hidden  : InpRiskPct_Regular;
   double tpRR     = isHidden ? InpTP_RR_Hidden    : InpTP_RR_Regular;
   string sigName  = isHidden ? "HidDiv" : "RegDiv";

   if (longSignal)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - atr * InpSL_ATR, digs);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(ask + slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / point, riskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, sigName + "_L");
      }
   }
   else if (shortSignal)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + atr * InpSL_ATR, digs);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(bid - slD * tpRR, digs);
         double lots = SC_CalcLotSize(slD / point, riskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, sigName + "_S");
      }
   }
}
