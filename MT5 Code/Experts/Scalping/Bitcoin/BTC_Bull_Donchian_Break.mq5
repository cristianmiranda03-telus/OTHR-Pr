//+------------------------------------------------------------------+
//| BTC_Bull_Donchian_Break.mq5                                      |
//| Strategy: Donchian Channel BULLISH Breakout Scalper              |
//| Asset: BTCUSD | Timeframe: M15 | Session: Any (24/7 BTC)         |
//| Logic: Price closes above the highest high of last N bars        |
//|        (Donchian upper break). Trend filter: EMA50 > EMA100.     |
//|        Volume must be above average to validate break.           |
//|        Classic Turtle-style breakout adapted for crypto scalping. |
//| Magic: 200006                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Donchian Settings ==="
input int    InpDon_Period     = 20;   // Donchian period
input int    InpEMA_Fast       = 50;
input int    InpEMA_Slow       = 100;
input double InpVol_Mult       = 1.2;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.5;
input double InpTP_ATR_Mult    = 3.0;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200006;

CTrade   g_trade;
datetime g_lastBarM15 = 0;

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
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double donHigh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpDon_Period, 2); // shift 2 = exclude current
   double close   = SC_Close(_Symbol, PERIOD_M15, 1);
   double ema50   = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Fast, 1);
   double ema100  = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Slow, 1);
   double vol     = (double)SC_Volume(_Symbol, PERIOD_M15, 1);
   double avgVol  = SC_AvgVolume(_Symbol, PERIOD_M15, 20, 2);
   double atr     = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0) return;

   bool breakout  = (close > donHigh);
   bool trend     = (ema50 > ema100);
   bool volOK     = (avgVol <= 0 || vol >= avgVol * InpVol_Mult);

   if (breakout && trend && volOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_Bull_Donchian_Break");
   }
}
