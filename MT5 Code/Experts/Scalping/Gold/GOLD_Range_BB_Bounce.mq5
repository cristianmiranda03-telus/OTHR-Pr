//+------------------------------------------------------------------+
//| GOLD_Range_BB_Bounce.mq5                                         |
//| Strategy: Bollinger Bands Mean Reversion - RANGE Scalper         |
//| Asset: XAUUSD | Timeframe: M5 | Session: Any (best in Asia)      |
//| Logic: Price touches lower BB + RSI < 35 = buy to middle.        |
//|        Price touches upper BB + RSI > 65 = sell to middle.       |
//|        Confirm with EMA21 (price near or crossing it = range).   |
//| Magic: 100003                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Bollinger Bands ==="
input int    InpBB_Period      = 20;     // BB period
input double InpBB_Dev         = 2.0;   // BB deviation
input int    InpRSI_Period     = 14;
input double InpRSI_OB         = 65.0;  // RSI overbought
input double InpRSI_OS         = 35.0;  // RSI oversold

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.5;
input double InpTP_BB_Middle   = true;  // TP at BB middle band (true) or fixed ATR
input double InpTP_ATR_Mult    = 1.8;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100003;

CTrade  g_trade;
datetime g_lastBarM5 = 0;

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
   if (SC_TotalPositions(InpMagic) > 0) return;

   double upper, middle, lower;
   SC_GetBB(_Symbol, PERIOD_M5, InpBB_Period, InpBB_Dev, 1, upper, middle, lower);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0 || upper <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Buy bounce at lower band
   if (close <= lower && rsi <= InpRSI_OS)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(middle, digits);  // TP = middle band
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Range_BB_Bounce_BUY");
   }
   // Sell rejection at upper band
   else if (close >= upper && rsi >= InpRSI_OB)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(middle, digits);  // TP = middle band
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Range_BB_Bounce_SELL");
   }
}
