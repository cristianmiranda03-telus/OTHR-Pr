//+------------------------------------------------------------------+
//| SP500_NY_Open_Bear.mq5                                           |
//| Strategy: NY Open BEARISH Gap & Go Scalper                       |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY open 13:30 UTC  |
//| Logic: First 5-min candle is bearish with large range.           |
//|        Sell break of first candle low in first 30 minutes.       |
//| Magic: 300005                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== NY Open Settings ==="
input int    InpEntryWindowMin = 45;
input double InpMinCandleATR   = 0.8;
input int    InpEMA_Trend      = 21;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 2.0;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300005;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
double   g_firstCandleLow = 1e9;
bool     g_entryDone = false;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;

   MqlDateTime dt;
   TimeToStruct(TimeGMT() + InpUTCOffset * 3600, dt);
   int h = dt.hour; int m = dt.min;
   int minOfDay = h * 60 + m;

   if (h == 13 && m < 5) { g_firstCandleLow = 1e9; g_entryDone = false; }

   if (minOfDay == 13 * 60 + 30)
   {
      double firstClose = SC_Close(_Symbol, PERIOD_M5, 1);
      double firstOpen  = SC_Open(_Symbol, PERIOD_M5, 1);
      double atr        = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
      if (firstClose < firstOpen && (firstOpen - firstClose) > atr * InpMinCandleATR)
         g_firstCandleLow = SC_Low(_Symbol, PERIOD_M5, 1);
   }

   if (minOfDay < 13 * 60 + 30 || minOfDay > 13 * 60 + 30 + InpEntryWindowMin) return;
   if (g_firstCandleLow >= 1e9 || g_entryDone || SC_TotalPositions(InpMagic) > 0) return;

   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool breakLow = (close < g_firstCandleLow);
   bool belowEMA = (close < ema21);

   if (breakLow && belowEMA)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_NY_Open_Bear"))
         g_entryDone = true;
   }
}
