//+------------------------------------------------------------------+
//| Gold_MFI_SmartMoney.mq5                                          |
//| Money Flow / Money Concept: MFI para XAU scalping               |
//| MFI sobreventa -> long; MFI sobrecompra -> short                 |
//| Magic 102003                                                      |
//+------------------------------------------------------------------+
#property copyright "Gold AI SMC Wyckoff"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"
#include "SMC_Wyckoff_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== MFI ==="
input int    InpMFI_Period   = 14;
input double InpMFI_Oversold  = 25.0;
input double InpMFI_Overbought = 75.0;

input group "=== Session ==="
input bool   InpOnlyAsian    = false;
input int    InpAsianStart   = 0;
input int    InpAsianEnd     = 9;
input int    InpUTCOffset    = 0;

input group "=== Risk ==="
input double InpRiskPct     = 0.4;
input double InpSL_ATR      = 1.0;
input double InpTP_RR      = 1.5;
input int    InpATR_Period  = 14;
input double InpMinLot      = 0.01;
input double InpMaxLot      = 0.5;
input int    InpMaxSpread   = 80;

input group "=== Trade ==="
input int    InpMagic       = 102003;

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

bool InSession()
{
   if (InpOnlyAsian) return SC_IsAsianSessionUTC(InpAsianStart, InpAsianEnd);
   return SC_IsLondonSession(InpUTCOffset) || SC_IsNYSession(InpUTCOffset);
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!InSession()) return;
   if (!SC_IsNewBar(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double mfi = Math_MFI(_Symbol, InpTF, InpMFI_Period, 1);
   double mfiPrev = Math_MFI(_Symbol, InpTF, InpMFI_Period, 2);
   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (mfi <= InpMFI_Oversold && mfiPrev <= InpMFI_Oversold)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - atr * InpSL_ATR, digits);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp = NormalizeDouble(ask + slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "MFI_L");
      }
      return;
   }

   if (mfi >= InpMFI_Overbought && mfiPrev >= InpMFI_Overbought)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(bid + atr * InpSL_ATR, digits);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp = NormalizeDouble(bid - slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "MFI_S");
      }
   }
}
