//+------------------------------------------------------------------+
//| GOLD_Bear_RSI_Rejection.mq5                                      |
//| Strategy: RSI Overbought Rejection - BEARISH Scalper             |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY             |
//| Logic: RSI rises above 70 (overbought) then crosses back below   |
//|        65. Price must be below EMA50 (downtrend context).        |
//|        Enter sell on the cross with ATR-based SL/TP.             |
//| Magic: 100010                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== RSI Rejection Settings ==="
input int    InpRSI_Period     = 14;
input double InpRSI_OB_Level   = 70.0;
input double InpRSI_Entry      = 65.0;
input int    InpEMA_Trend      = 50;

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
input int    InpMagic          = 100010;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
bool     g_rsiWasAboveOB = false;

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

   if (rsi1 > InpRSI_OB_Level) g_rsiWasAboveOB = true;

   bool rejection  = g_rsiWasAboveOB && (rsi1 <= InpRSI_Entry) && (rsi2 > InpRSI_Entry);
   bool downtrend  = (close < ema50);

   if (rejection && downtrend && SC_TotalPositions(InpMagic) == 0)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Bear_RSI_Rejection"))
         g_rsiWasAboveOB = false;
   }
   else if (rsi1 <= 50) g_rsiWasAboveOB = false;
}
