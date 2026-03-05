//+------------------------------------------------------------------+
//| SP500_Range_BB_Middle.mq5                                        |
//| Strategy: Bollinger Band Middle Line RANGE Scalper               |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY mid-session     |
//| Logic: When SP500 is ranging (BB bands contracting), price       |
//|        oscillates around the BB middle (SMA20).                 |
//|        RSI crosses 45 from below = buy to upper band.           |
//|        RSI crosses 55 from above = sell to lower band.          |
//|        Filters chop with narrow ATR condition.                  |
//| Magic: 300013                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== BB Middle Settings ==="
input int    InpBB_Period      = 20;
input double InpBB_Dev         = 2.0;
input int    InpRSI_Period     = 14;
input double InpRSI_Buy        = 45.0;
input double InpRSI_Sell       = 55.0;
input double InpRange_ATR      = 1.5;  // BB width < N*ATR = range day

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 0.8;
input double InpTP_ATR_Mult    = 1.2;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300013;

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

   double upper, mid, lower;
   SC_GetBB(_Symbol, PERIOD_M5, InpBB_Period, InpBB_Dev, 1, upper, mid, lower);
   double rsi1 = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2 = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   double close= SC_Close(_Symbol, PERIOD_M5, 1);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0 || upper <= 0) return;

   bool rangeDay = ((upper - lower) < atr * InpRange_ATR);
   int  digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (rangeDay && rsi1 >= InpRSI_Buy && rsi2 < InpRSI_Buy && close < mid)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(mid + atr * 0.3, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "SP500_BB_Mid_BUY");
   }
   else if (rangeDay && rsi1 <= InpRSI_Sell && rsi2 > InpRSI_Sell && close > mid)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(mid - atr * 0.3, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_BB_Mid_SELL");
   }
}
