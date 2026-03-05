//+------------------------------------------------------------------+
//| SP500_Range_CCI_Oscillator.mq5                                   |
//| Strategy: CCI Oscillator RANGE Scalper                           |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY mid-session     |
//| Logic: In SP500 range days (BB width tight), CCI oscillates      |
//|        between ±100 and ±200.                                    |
//|        CCI crosses -100 upward from below = buy.                |
//|        CCI crosses +100 downward from above = sell.             |
//|        BB squeeze condition validates range environment.         |
//| Magic: 300008                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== CCI Range Settings ==="
input int    InpCCI_Period     = 14;
input double InpCCI_Buy        = -100.0;
input double InpCCI_Sell       = 100.0;
input int    InpBB_Period      = 20;
input double InpBB_Dev         = 2.0;
input double InpBB_SqzATR      = 2.0;  // BB width < N*ATR = range

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 1.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300008;

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
   double cci1 = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 1);
   double cci2 = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 2);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0 || upper <= 0) return;

   bool squeeze = ((upper - lower) < atr * InpBB_SqzATR);
   int  digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (squeeze && cci1 >= InpCCI_Buy && cci2 < InpCCI_Buy)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "SP500_CCI_Range_BUY");
   }
   else if (squeeze && cci1 <= InpCCI_Sell && cci2 > InpCCI_Sell)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_CCI_Range_SELL");
   }
}
