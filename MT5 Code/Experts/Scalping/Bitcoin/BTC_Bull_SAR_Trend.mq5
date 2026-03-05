//+------------------------------------------------------------------+
//| BTC_Bull_SAR_Trend.mq5                                           |
//| Strategy: Parabolic SAR BULLISH Trend Scalper                    |
//| Asset: BTCUSD | Timeframe: M5 | Session: NY + London             |
//| Logic: SAR flips from above price to below price (bull flip)     |
//|        + price above EMA50 + RSI > 50 = buy.                    |
//|        SAR provides dynamic trailing stop concept.               |
//|        Fast exits when SAR flips back above price.               |
//| Magic: 200014                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Parabolic SAR Settings ==="
input double InpSAR_Step       = 0.02;
input double InpSAR_Max        = 0.2;
input int    InpEMA_Trend      = 50;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.5;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200014;

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
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double sar1  = SC_GetSAR(_Symbol, PERIOD_M5, InpSAR_Step, InpSAR_Max, 1);
   double sar2  = SC_GetSAR(_Symbol, PERIOD_M5, InpSAR_Step, InpSAR_Max, 2);
   double close1= SC_Close(_Symbol, PERIOD_M5, 1);
   double close2= SC_Close(_Symbol, PERIOD_M5, 2);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, 14, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   // SAR was above price (bearish), now below price (bullish flip)
   bool sarFlipBull = (sar1 < close1 && sar2 > close2);
   bool uptrend     = (close1 > ema50);
   bool rsiOK       = (rsi > 50);

   if (sarFlipBull && uptrend && rsiOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_Bull_SAR_Trend");
   }
}
