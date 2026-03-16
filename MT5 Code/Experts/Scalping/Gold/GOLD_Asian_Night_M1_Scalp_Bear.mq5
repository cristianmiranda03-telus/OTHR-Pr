//+------------------------------------------------------------------+
//| GOLD_Asian_Night_M1_Scalp_Bear.mq5                               |
//| Oro sesion Asia M1: 2 alcistas + vela bajista reversal          |
//| Magic 101106                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Asian"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Session UTC ==="
input int    InpAsianStartUTC = 0;
input int    InpAsianEndUTC   = 9;

input group "=== M1 Pattern ==="
input int    InpBullBars      = 2;
input double InpMinBodyATR    = 0.25;

input group "=== Risk ==="
input double InpRiskPct       = 0.25;
input double InpSL_ATR_Mult   = 0.8;
input double InpTP_RR         = 1.0;
input int    InpATR_Period    = 14;
input double InpMinLot        = 0.01;
input double InpMaxLot        = 0.3;
input int    InpMaxSpread     = 120;

input group "=== Trade ==="
input int    InpMagic         = 101106;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bearish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsAsianSessionUTC(InpAsianStartUTC, InpAsianEndUTC)) return;

   datetime t[];
   ArraySetAsSeries(t, true);
   if (CopyTime(_Symbol, PERIOD_M1, 0, 1, t) < 1) return;
   if (t[0] == g_lastBar) return;
   g_lastBar = t[0];
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BearOK(_Symbol, InpMTF_MinScore)) return;

   int n = InpBullBars + 1;
   double o[], c[];
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, PERIOD_M1, 1, n, o) < n || CopyClose(_Symbol, PERIOD_M1, 1, n, c) < n) return;

   for (int i = 1; i <= InpBullBars; i++)
      if (c[i] <= o[i]) return;

   if (c[0] >= o[0]) return;
   double body = o[0] - c[0];
   double atr = SC_GetATR(_Symbol, PERIOD_M1, InpATR_Period, 1);
   if (atr <= 0 || body < atr * InpMinBodyATR) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double h1 = SC_High(_Symbol, PERIOD_M1, 1);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(h1 + atr * 0.15, digits);
   double slD = sl - bid;
   if (slD <= 0) return;
   double tp = NormalizeDouble(bid - slD * InpTP_RR, digits);
   double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
   g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Asian_M1_S");
}
