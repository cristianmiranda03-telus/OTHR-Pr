//+------------------------------------------------------------------+
//| GOLD_Asian_Night_RSI_Bull.mq5                                    |
//| Gold Asian session UTC; mean reversion RSI oversold bounce       |
//| TF M1-M15 input. Magic 101101                                     |
//| UTC-6 night: Asian window 00-09 UTC = 18:00-03:00 local         |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Asian"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Session UTC ==="
input int    InpAsianStartUTC = 0;
input int    InpAsianEndUTC   = 9;

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== RSI Bounce ==="
input int    InpRSI_Period   = 14;
input double InpRSI_Oversold = 32.0;
input int    InpRSI_BarsBack = 2;

input group "=== Risk ==="
input double InpRiskPct     = 0.35;
input double InpSL_ATR_Mult = 1.1;
input double InpTP_RR       = 1.2;
input int    InpATR_Period  = 14;
input double InpMinLot     = 0.01;
input double InpMaxLot     = 0.5;
input int    InpMaxSpread   = 100;

input group "=== Trade ==="
input int    InpMagic       = 101101;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bullish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

bool NewBarTF(ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime t[];
   ArraySetAsSeries(t, true);
   if (CopyTime(_Symbol, tf, 0, 1, t) < 1) return false;
   if (t[0] == last) return false;
   last = t[0];
   return true;
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
   if (!SC_IsAsianSessionUTC(InpAsianStartUTC, InpAsianEndUTC)) return;
   if (!NewBarTF(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BullOK(_Symbol, InpMTF_MinScore)) return;

   double rsi1 = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double rsi2 = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 2);
   double rsi3 = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 3);

   bool wasOversold = (rsi2 <= InpRSI_Oversold || (InpRSI_BarsBack >= 2 && rsi3 <= InpRSI_Oversold));
   bool crossUp = (rsi1 > InpRSI_Oversold && rsi2 <= InpRSI_Oversold);
   if (!wasOversold && !crossUp) return;

   double c1 = SC_Close(_Symbol, InpTF, 1);
   double o1 = SC_Open(_Symbol, InpTF, 1);
   if (c1 <= o1) return;

   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
   double slD = ask - sl;
   double tp = NormalizeDouble(ask + slD * InpTP_RR, digits);
   double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
   g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Asian_RSI_Bull");
}
