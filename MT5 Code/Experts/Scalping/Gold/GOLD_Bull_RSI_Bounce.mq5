//+------------------------------------------------------------------+
//| GOLD_Bull_RSI_Bounce.mq5                                         |
//| Strategy: RSI Oversold Bounce - BULLISH Scalper                  |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY             |
//| Logic: RSI dips below 30 (oversold) then crosses back above 35.  |
//|        Price must be above EMA50 (uptrend context).              |
//|        Enter on the cross with ATR-based SL/TP.                  |
//| Magic: 100009                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== RSI Bounce Settings ==="
input int    InpRSI_Period     = 14;
input double InpRSI_OS_Level   = 30.0;  // Oversold level
input double InpRSI_Entry      = 35.0;  // Cross-back entry
input int    InpEMA_Trend      = 50;    // Trend filter EMA

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_ATR_Mult    = 2.2;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100009;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
bool     g_rsiWasBelowOS = false;

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

   double rsi1  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend,  1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   // Track if RSI was oversold
   if (rsi1 < InpRSI_OS_Level) g_rsiWasBelowOS = true;

   bool bounce   = g_rsiWasBelowOS && (rsi1 >= InpRSI_Entry) && (rsi2 < InpRSI_Entry);
   bool uptrend  = (close > ema50);

   if (bounce && uptrend && SC_TotalPositions(InpMagic) == 0)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Bull_RSI_Bounce"))
         g_rsiWasBelowOS = false;
   }
   else if (rsi1 >= 50) g_rsiWasBelowOS = false; // reset flag when RSI normalizes
}
