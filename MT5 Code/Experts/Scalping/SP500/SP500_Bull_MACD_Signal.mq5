//+------------------------------------------------------------------+
//| SP500_Bull_MACD_Signal.mq5                                       |
//| Strategy: MACD Signal Line Cross BULLISH Scalper                 |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY session          |
//| Logic: MACD line crosses above signal line (below zero = strong).|
//|        Combined with: EMA50 slope up + Donchian breakout.       |
//|        Frequent signals during trending NY session.              |
//| Magic: 300011                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== MACD Settings ==="
input int    InpMACD_Fast      = 12;
input int    InpMACD_Slow      = 26;
input int    InpMACD_Signal    = 9;
input int    InpEMA_Trend      = 50;
input int    InpDon_Period     = 10;

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
input int    InpMagic          = 300011;

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

   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double ema50p = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 3);
   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double donH   = SC_GetHighestHigh(_Symbol, PERIOD_M5, InpDon_Period, 2);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool macdCross = (macd1 > sig1 && macd2 <= sig2);
   bool emaUp     = (ema50 > ema50p);
   bool donBreak  = (close >= donH);

   if (macdCross && emaUp && donBreak)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "SP500_Bull_MACD_Signal");
   }
}
