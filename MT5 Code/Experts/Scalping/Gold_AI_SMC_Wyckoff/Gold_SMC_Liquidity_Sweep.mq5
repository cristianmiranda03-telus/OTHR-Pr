//+------------------------------------------------------------------+
//| Gold_SMC_Liquidity_Sweep.mq5                                     |
//| Smart Money: barrido de liquidez (sweep highs/lows) + reversal   |
//| Nuevo high luego cierre abajo -> short; nuevo low luego cierre   |
//| arriba -> long. Magic 102005                                      |
//+------------------------------------------------------------------+
#property copyright "Gold AI SMC Wyckoff"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"
#include "SMC_Wyckoff_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== Liquidity Sweep ==="
input int    InpSweepLookback = 15;

input group "=== Session ==="
input bool   InpOnlyAsian   = false;
input int    InpAsianStart   = 0;
input int    InpAsianEnd     = 9;
input int    InpUTCOffset    = 0;

input group "=== Risk ==="
input double InpRiskPct     = 0.4;
input double InpSL_ATR      = 1.0;
input double InpTP_RR      = 1.5;
input int    InpATR_Period  = 14;
input double InpMinLot      = 0.01;
input double InpMaxLot      = 0.5;
input int    InpMaxSpread   = 80;

input group "=== Trade ==="
input int    InpMagic       = 102005;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min score magnitude to take directional trade (1-3)

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

bool InSession()
{
   if (InpOnlyAsian) return SC_IsAsianSessionUTC(InpAsianStart, InpAsianEnd);
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

   double sweepLevel = 0;
   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (SMC_SweepHighs(_Symbol, InpTF, 1, InpSweepLookback, sweepLevel) && mtfScore <= InpMTF_MinScore)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(sweepLevel + atr * InpSL_ATR, digits);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp = NormalizeDouble(bid - slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "SMC_Sweep_S");
      }
      return;
   }

   if (SMC_SweepLows(_Symbol, InpTF, 1, InpSweepLookback, sweepLevel) && mtfScore >= -InpMTF_MinScore)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(sweepLevel - atr * InpSL_ATR, digits);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp = NormalizeDouble(ask + slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "SMC_Sweep_L");
      }
   }
}
