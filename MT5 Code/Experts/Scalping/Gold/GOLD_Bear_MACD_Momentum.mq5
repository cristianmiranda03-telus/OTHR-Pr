//+------------------------------------------------------------------+
//| GOLD_Bear_MACD_Momentum.mq5                                      |
//| Strategy: MACD Bearish Momentum Scalper                          |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY             |
//| Logic: MACD histogram turns negative (crosses zero from above)   |
//|        + EMA21 < EMA50 (downtrend on M5) + RSI < 50.            |
//| Magic: 100013                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== MACD Settings ==="
input int    InpMACD_Fast      = 8;
input int    InpMACD_Slow      = 21;
input int    InpMACD_Signal    = 5;
input int    InpEMA_Fast       = 21;
input int    InpEMA_Slow       = 50;

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
input int    InpMagic          = 100013;

CTrade   g_trade;
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
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double hist1  = macd1 - sig1;
   double hist2  = macd2 - sig2;
   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, 14, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool histCrossDown = (hist1 < 0 && hist2 >= 0);
   bool downtrend     = (ema21 < ema50);
   bool rsiOK         = (rsi < 50);

   if (histCrossDown && downtrend && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Bear_MACD_Momentum");
   }
}
