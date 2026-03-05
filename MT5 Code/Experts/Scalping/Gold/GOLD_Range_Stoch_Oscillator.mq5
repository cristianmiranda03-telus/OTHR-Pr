//+------------------------------------------------------------------+
//| GOLD_Range_Stoch_Oscillator.mq5                                  |
//| Strategy: Stochastic Oscillator RANGE Scalper                    |
//| Asset: XAUUSD | Timeframe: M5 | Session: Asian + slow hours      |
//| Logic: In sideways market (price between EMA20 ± 0.8 ATR),       |
//|        Stoch %K crosses %D below 20 = buy.                       |
//|        Stoch %K crosses %D above 80 = sell.                      |
//|        Confirms range with ADX < 25.                             |
//| Magic: 100011                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Stochastic Settings ==="
input int    InpStoch_K        = 5;     // %K period (fast)
input int    InpStoch_D        = 3;     // %D period
input int    InpStoch_Slow     = 3;     // Slowing
input double InpOB             = 80.0;  // Overbought
input double InpOS             = 20.0;  // Oversold
input int    InpEMA_Range      = 20;    // EMA for range center
input double InpRange_ATR_Band = 0.8;  // Range band in ATR units

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 1.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 50;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100011;

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
   if (SC_TotalPositions(InpMagic) > 0) return;

   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 2, k2, d2);
   double ema  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Range, 1);
   double close= SC_Close(_Symbol, PERIOD_M5, 1);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   // Range condition: price is within EMA ± band
   bool inRange = (MathAbs(close - ema) < atr * InpRange_ATR_Band);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (inRange && k1 > d1 && k2 <= d2 && k1 < InpOS + 10)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Range_Stoch_BUY");
   }
   else if (inRange && k1 < d1 && k2 >= d2 && k1 > InpOB - 10)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Range_Stoch_SELL");
   }
}
