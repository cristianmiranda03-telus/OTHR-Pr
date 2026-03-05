//+------------------------------------------------------------------+
//| BTC_Asian_Range_Scalp.mq5                                        |
//| Strategy: Asian Session RANGE Scalper (both directions)          |
//| Asset: BTCUSD | Timeframe: M15 | Session: Tokyo 00:00-07:00 UTC  |
//| Logic: BTC consolidates in tight range during Asian session.     |
//|        Trade bounces off Asian range high/low with RSI & CCI.   |
//|        High = sell zone, Low = buy zone. TP = range midpoint.   |
//| Magic: 200013                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Range Settings ==="
input int    InpRangeBars      = 4;     // M15 bars to define current range segment
input double InpTouchBuffer    = 0.3;   // ATR distance from range edge to trigger
input int    InpRSI_Period     = 7;     // Fast RSI
input int    InpCCI_Period     = 14;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 1.2;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.05;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200013;

CTrade   g_trade;
datetime g_lastBarM15 = 0;

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
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;
   if (!SC_IsTokyoSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double rangeHigh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpRangeBars, 1);
   double rangeLow  = SC_GetLowestLow(_Symbol, PERIOD_M15,  InpRangeBars, 1);
   double close     = SC_Close(_Symbol, PERIOD_M15, 1);
   double atr       = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   double rsi       = SC_GetRSI(_Symbol, PERIOD_M15, InpRSI_Period, 1);
   double cci       = SC_GetCCI(_Symbol, PERIOD_M15, InpCCI_Period, 1);
   if (atr <= 0 || rangeHigh <= rangeLow) return;

   double mid    = (rangeHigh + rangeLow) / 2.0;
   double buf    = atr * InpTouchBuffer;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Buy from range low
   if (close <= rangeLow + buf && rsi < 45 && cci < -50)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(mid, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_Asian_Range_BUY");
   }
   // Sell from range high
   else if (close >= rangeHigh - buf && rsi > 55 && cci > 50)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(mid, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_Asian_Range_SELL");
   }
}
