//+------------------------------------------------------------------+
//| SP500_Bear_Supertrend.mq5                                        |
//| Strategy: Supertrend Indicator BEARISH Scalper                   |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY + London/NY     |
//| Logic: Supertrend flips from bullish to bearish = sell signal.  |
//|        Confirms with RSI < 50 and EMA21 slope negative.         |
//| Magic: 300010                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Supertrend Settings ==="
input int    InpST_ATR_Period  = 10;
input double InpST_Multiplier  = 3.0;
input int    InpEMA_Trend      = 21;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300010;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

int GetSupertrendDir(int shift)
{
   double hl2_1  = (SC_High(_Symbol, PERIOD_M5, shift) + SC_Low(_Symbol, PERIOD_M5, shift)) / 2.0;
   double hl2_2  = (SC_High(_Symbol, PERIOD_M5, shift+1) + SC_Low(_Symbol, PERIOD_M5, shift+1)) / 2.0;
   double atr1   = SC_GetATR(_Symbol, PERIOD_M5, InpST_ATR_Period, shift);
   double atr2   = SC_GetATR(_Symbol, PERIOD_M5, InpST_ATR_Period, shift+1);
   double close1 = SC_Close(_Symbol, PERIOD_M5, shift);
   double upper2 = hl2_2 + InpST_Multiplier * atr2;
   double lower2 = hl2_2 - InpST_Multiplier * atr2;
   double close2 = SC_Close(_Symbol, PERIOD_M5, shift+1);
   if (close1 > upper2) return 1;
   if (close1 < lower2) return -1;
   return (close2 > upper2) ? 1 : -1;
}

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

   int dir1  = GetSupertrendDir(1);
   int dir2  = GetSupertrendDir(2);
   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double ema21p = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 3);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, 14, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool stFlip  = (dir1 == -1 && dir2 == 1);
   bool emaDown = (ema21 < ema21p);
   bool rsiOK   = (rsi < 50);

   if (stFlip && emaDown && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_Bear_Supertrend");
   }
}
