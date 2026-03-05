//+------------------------------------------------------------------+
//| SP500_Bear_EMA_Trend.mq5                                         |
//| Strategy: EMA Cross BEARISH Trend Scalper                        |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY 13:00-22:00 UTC |
//| Logic: EMA9 crosses below EMA21 while both below EMA50.         |
//|        RSI < 48 confirms bearish momentum.                       |
//| Magic: 300002                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== EMA Trend Settings ==="
input int    InpEMA_Fast       = 9;
input int    InpEMA_Mid        = 21;
input int    InpEMA_Slow       = 50;
input int    InpRSI_Period     = 14;
input double InpRSI_Max        = 48.0;

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
input int    InpMagic          = 300002;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

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
   if (!SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema9  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Mid,  1);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double ema9p = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 2);
   double ema21p= SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Mid,  2);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool cross    = (ema9 < ema21 && ema9p >= ema21p);
   bool below50  = (ema9 < ema50 && ema21 < ema50);
   bool rsiOK    = (rsi <= InpRSI_Max);

   if (cross && below50 && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_Bear_EMA_Trend");
   }
}
