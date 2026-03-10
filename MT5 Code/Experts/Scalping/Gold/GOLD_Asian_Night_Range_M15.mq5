//+------------------------------------------------------------------+
//| GOLD_Asian_Night_Range_M15.mq5                                  |
//| Oro - Sesion Asia: rango ultimas N velas, fade en extremos       |
//| Pensado para M15 (o M5); define techo/suelo y vende techo /      |
//| compra suelo con TP al mid-range. Magic 101104                   |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Asian"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Session UTC ==="
input int    InpAsianStartUTC = 0;
input int    InpAsianEndUTC   = 9;

input group "=== Timeframe (M15 o M5) ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M15;

input group "=== Range ==="
input int    InpRangeBars    = 12;     // lookback para high/low sesion corta
input double InpBufferATR    = 0.15;   // distancia minima al borde en ATRs

input group "=== Risk ==="
input double InpRiskPct      = 0.3;
input double InpSL_ATR_Mult  = 0.9;
input double InpTP_MidRange = true;  // TP en punto medio del rango
input double InpTP_RR        = 1.0;   // si InpTP_MidRange false
input int    InpATR_Period   = 14;
input double InpMinLot       = 0.01;
input double InpMaxLot       = 0.5;
input int    InpMaxSpread    = 100;

input group "=== Trade ==="
input int    InpMagic        = 101104;

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

   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;

   double rangeHigh = SC_GetHighestHigh(_Symbol, InpTF, InpRangeBars, 1);
   double rangeLow  = SC_GetLowestLow(_Symbol, InpTF, InpRangeBars, 1);
   if (rangeHigh <= rangeLow) return;

   double mid = (rangeHigh + rangeLow) * 0.5;
   double buf = atr * InpBufferATR;
   double c1  = SC_Close(_Symbol, InpTF, 1);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Cerca del techo -> venta hacia mid
   if (SC_CountPositions(POSITION_TYPE_SELL, InpMagic) == 0 && c1 >= rangeHigh - buf)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(rangeHigh + atr * InpSL_ATR_Mult, digits);
      double slD = sl - bid;
      if (slD <= 0) return;
      double tp  = InpTP_MidRange ? NormalizeDouble(mid, digits) : NormalizeDouble(bid - slD * InpTP_RR, digits);
      if (tp >= bid) tp = NormalizeDouble(bid - slD * InpTP_RR, digits);
      double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Asian_Range_S");
      return;
   }

   // Cerca del suelo -> compra hacia mid
   if (SC_CountPositions(POSITION_TYPE_BUY, InpMagic) == 0 && c1 <= rangeLow + buf)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(rangeLow - atr * InpSL_ATR_Mult, digits);
      double slD = ask - sl;
      if (slD <= 0) return;
      double tp  = InpTP_MidRange ? NormalizeDouble(mid, digits) : NormalizeDouble(ask + slD * InpTP_RR, digits);
      if (tp <= ask) tp = NormalizeDouble(ask + slD * InpTP_RR, digits);
      double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Asian_Range_L");
   }
}
