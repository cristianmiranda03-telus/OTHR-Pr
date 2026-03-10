//+------------------------------------------------------------------+
//| GOLD_Asian_Night_RSI_Bear.mq5                                   |
//| Oro - Sesion Asia UTC; mean reversion bajista                    |
//| RSI sale de sobrecompra + cierre bajista. TF M1-M15. Magic 101102|
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Asian"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Session UTC ==="
input int    InpAsianStartUTC = 0;
input int    InpAsianEndUTC   = 9;

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== RSI Fade ==="
input int    InpRSI_Period    = 14;
input double InpRSI_Overbought = 68.0;

input group "=== Risk ==="
input double InpRiskPct       = 0.35;
input double InpSL_ATR_Mult   = 1.1;
input double InpTP_RR         = 1.2;
input int    InpATR_Period    = 14;
input double InpMinLot        = 0.01;
input double InpMaxLot        = 0.5;
input int    InpMaxSpread     = 100;

input group "=== Trade ==="
input int    InpMagic         = 101102;

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

bool SC_IsNewBarTF(ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime t[]; ArraySetAsSeries(t, true);
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
   if (!SC_IsNewBarTF(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double rsi1 = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double rsi2 = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 2);
   bool wasOverbought = (rsi2 >= InpRSI_Overbought);
   bool crossDown       = (rsi1 < InpRSI_Overbought && rsi2 >= InpRSI_Overbought);
   if (!wasOverbought && !crossDown) return;

   double c1 = SC_Close(_Symbol, InpTF, 1);
   double o1 = SC_Open(_Symbol, InpTF, 1);
   if (c1 >= o1) return;

   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl     = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
   double slD    = sl - bid;
   double tp     = NormalizeDouble(bid - slD * InpTP_RR, digits);
   double slPts  = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lots   = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
   g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Asian_RSI_Bear");
}
