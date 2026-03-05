//+------------------------------------------------------------------+
//| GOLD_NY_Open_Bull_Surge.mq5                                      |
//| Strategy: New York Open BULLISH Surge Scalper                    |
//| Asset: XAUUSD | Timeframe: M5 | Session: NY open 13:00 UTC       |
//| Logic: NY open is the highest volatility window for Gold.        |
//|        Price above 30-bar SMA + MACD bullish crossover at or     |
//|        just after 13:00 UTC = buy with tight ATR stop.           |
//| Magic: 100006                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== NY Open Settings ==="
input int    InpSMA_Period     = 30;    // SMA trend filter
input int    InpMACD_Fast      = 12;
input int    InpMACD_Slow      = 26;
input int    InpMACD_Signal    = 9;
input int    InpEntryWindowMin = 60;   // Window after 13:00 UTC (minutes)

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 2.0;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100006;

CTrade  g_trade;
datetime g_lastBarM5 = 0;
bool     g_entryDone = false;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
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

   // Reset daily
   if (h == 12 && m < 5) g_entryDone = false;

   // Window: 13:00 - 14:00 UTC
   if (minOfDay < 13 * 60 || minOfDay > 13 * 60 + InpEntryWindowMin) return;
   if (g_entryDone || SC_TotalPositions(InpMagic) > 0) return;

   double sma   = SC_GetSMA(_Symbol, PERIOD_M5, InpSMA_Period, 1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double atr = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool aboveSMA = (close > sma);
   bool macdCross = (macd1 > sig1 && macd2 <= sig2); // fresh crossover

   if (aboveSMA && macdCross)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_NY_Open_Bull_Surge"))
         g_entryDone = true;
   }
}
