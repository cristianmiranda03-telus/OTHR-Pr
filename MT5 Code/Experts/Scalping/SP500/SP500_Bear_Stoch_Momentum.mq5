//+------------------------------------------------------------------+
//| SP500_Bear_Stoch_Momentum.mq5                                    |
//| Strategy: Stochastic Momentum BEARISH Scalper                    |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY + London/NY     |
//| Logic: Stochastic %K crosses below %D from overbought zone (>70) |
//|        + EMA13 < EMA34 (trend down) + bearish candle close.     |
//| Magic: 300015                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Stochastic Settings ==="
input int    InpStoch_K        = 5;
input int    InpStoch_D        = 3;
input int    InpStoch_Slow     = 3;
input double InpOB_Level       = 70.0;
input int    InpEMA_Fast       = 13;
input int    InpEMA_Slow       = 34;

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
input int    InpMagic          = 300015;

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
   if (!SC_IsNYSession(InpUTCOffset) && !SC_IsLondonNYOverlap(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 2, k2, d2);
   double ema13 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema34 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double open  = SC_Open(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool stochSell  = (k1 < d1 && k2 >= d2 && k2 > InpOB_Level);
   bool downtrend  = (ema13 < ema34);
   bool bearClose  = (close < open);

   if (stochSell && downtrend && bearClose)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_Bear_Stoch_Momentum");
   }
}
