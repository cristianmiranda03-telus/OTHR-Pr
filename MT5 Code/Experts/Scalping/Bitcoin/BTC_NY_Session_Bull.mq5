//+------------------------------------------------------------------+
//| BTC_NY_Session_Bull.mq5                                          |
//| Strategy: New York Session BULLISH BTC Scalper                   |
//| Asset: BTCUSD | Timeframe: M5 | Session: NY 13:00-17:00 UTC      |
//| Logic: NY session brings highest BTC institutional volume.       |
//|        Stochastic K crosses D while below 50 and RSI > 45 =      |
//|        buy the intraday dip during NY session uptrend hours.     |
//|        EMA21 > EMA50 required as trend context.                  |
//| Magic: 200009                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== NY Session Bull Settings ==="
input int    InpStoch_K        = 5;
input int    InpStoch_D        = 3;
input int    InpStoch_Slow     = 3;
input double InpStoch_Max      = 50.0;  // Stoch must be below this for dip
input int    InpEMA_Fast       = 21;
input int    InpEMA_Slow       = 50;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_ATR_Mult    = 2.0;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200009;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

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
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 2, k2, d2);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, 14, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool stochBuy  = (k1 > d1 && k2 <= d2 && k1 < InpStoch_Max);
   bool uptrend   = (ema21 > ema50);
   bool rsiOK     = (rsi > 45);

   if (stochBuy && uptrend && rsiOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_NY_Session_Bull");
   }
}
