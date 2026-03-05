//+------------------------------------------------------------------+
//| BTC_Range_RSI_Scalp.mq5                                          |
//| Strategy: RSI Oscillation RANGE Scalper                          |
//| Asset: BTCUSD | Timeframe: M5 | Session: Asian consolidation      |
//| Logic: In a tight range (BB width < 1.5 ATR), RSI oscillates.   |
//|        RSI crosses above 40 from below = buy.                    |
//|        RSI crosses below 60 from above = sell.                   |
//|        BB squeeze detection ensures we're in range mode.         |
//| Magic: 200008                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== RSI Range Settings ==="
input int    InpRSI_Period     = 14;
input double InpRSI_Buy        = 40.0;  // RSI cross-up level
input double InpRSI_Sell       = 60.0;  // RSI cross-down level
input int    InpBB_Period      = 20;
input double InpBB_Dev         = 2.0;
input double InpBB_SqzATR      = 1.5;  // BB width < N*ATR = squeeze (range)

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 1.2;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.05;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200008;

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
   if (SC_TotalPositions(InpMagic) > 0) return;

   double upper, mid, lower;
   SC_GetBB(_Symbol, PERIOD_M5, InpBB_Period, InpBB_Dev, 1, upper, mid, lower);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double rsi1   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   if (atr <= 0 || upper <= 0) return;

   // Range confirmed: BB width < ATR threshold
   bool squeeze   = ((upper - lower) < atr * InpBB_SqzATR);
   int  digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (squeeze && rsi1 >= InpRSI_Buy && rsi2 < InpRSI_Buy)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_Range_RSI_BUY");
   }
   else if (squeeze && rsi1 <= InpRSI_Sell && rsi2 > InpRSI_Sell)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_Range_RSI_SELL");
   }
}
