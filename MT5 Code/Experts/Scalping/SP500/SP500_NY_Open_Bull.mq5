//+------------------------------------------------------------------+
//| SP500_NY_Open_Bull.mq5                                           |
//| Strategy: NY Open BULLISH Gap & Go Scalper                       |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY open 13:30 UTC  |
//| Logic: SP500 cash opens at 13:30 UTC (9:30 EST).                |
//|        First 5-min candle closes bullish with large range.       |
//|        Price > previous day close = gap-up continuation.        |
//|        Buy break of first candle high in first 30 minutes.       |
//| Magic: 300004                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== NY Open Settings ==="
input int    InpEntryWindowMin = 45;   // Minutes after 13:30 to trade
input double InpMinCandleATR   = 0.8;  // Min first candle size (ATR units)
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
input int    InpMagic          = 300004;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
double   g_firstCandleHigh = 0;
bool     g_entryDone  = false;

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

   // Reset at 13:00
   if (h == 13 && m < 5) { g_firstCandleHigh = 0; g_entryDone = false; }

   // Capture first 13:30 candle
   if (minOfDay == 13 * 60 + 30)
   {
      double firstClose = SC_Close(_Symbol, PERIOD_M5, 1);
      double firstOpen  = SC_Open(_Symbol, PERIOD_M5, 1);
      double atr        = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
      if (firstClose > firstOpen && (firstClose - firstOpen) > atr * InpMinCandleATR)
         g_firstCandleHigh = SC_High(_Symbol, PERIOD_M5, 1);
   }

   // Entry window: 13:30 to 14:15 UTC
   if (minOfDay < 13 * 60 + 30 || minOfDay > 13 * 60 + 30 + InpEntryWindowMin) return;
   if (g_firstCandleHigh <= 0 || g_entryDone || SC_TotalPositions(InpMagic) > 0) return;

   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool breakHigh = (close > g_firstCandleHigh);
   bool aboveEMA  = (close > ema21);

   if (breakHigh && aboveEMA)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "SP500_NY_Open_Bull"))
         g_entryDone = true;
   }
}
