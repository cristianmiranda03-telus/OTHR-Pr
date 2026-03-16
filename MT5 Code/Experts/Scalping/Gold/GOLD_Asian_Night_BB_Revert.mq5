//+------------------------------------------------------------------+
//| GOLD_Asian_Night_BB_Revert.mq5                                  |
//| Oro - Sesion Asia: reversion a la media Bollinger             |
//| Long: toca/cruza banda inferior; Short: banda superior          |
//| TF M1-M15. Magic 101103                                          |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Asian"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Session UTC ==="
input int    InpAsianStartUTC = 0;
input int    InpAsianEndUTC   = 9;

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== Bollinger ==="
input int    InpBB_Period    = 20;
input double InpBB_Dev       = 2.0;

input group "=== Risk ==="
input double InpRiskPct      = 0.35;
input double InpSL_ATR_Mult  = 1.0;
input double InpTP_RR        = 1.0;
input int    InpATR_Period   = 14;
input double InpMinLot       = 0.01;
input double InpMaxLot       = 0.5;
input int    InpMaxSpread    = 100;

input group "=== Trade ==="
input int    InpMagic        = 101103;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MaxScore = 1;      // Max trend score to allow range trade (0=flat, 1=loose)

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

bool SC_IsNewBarTF(ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime t[]; ArraySetAsSeries(t, true);
   if (CopyTime(_Symbol, tf, 0, 1, t) < 1) return false;
   if (t[0] == last) return false;
   last = t[0];
   return true;
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
   if (!SC_IsAsianSessionUTC(InpAsianStartUTC, InpAsianEndUTC)) return;
   if (!SC_IsNewBarTF(InpTF, g_lastBar)) return;
   if (InpUseMTF && !SC_MTF_RangeOK(_Symbol, InpMTF_MaxScore)) return;

   double upper, middle, lower;
   SC_GetBB(_Symbol, InpTF, InpBB_Period, InpBB_Dev, 1, upper, middle, lower);
   if (upper <= 0 || lower <= 0) return;

   double c1 = SC_Close(_Symbol, InpTF, 1);
   double l1 = SC_Low(_Symbol, InpTF, 1);
   double h1 = SC_High(_Symbol, InpTF, 1);
   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   if (atr <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Long: precio toco banda inferior y cierra de vuelta dentro
   if (SC_CountPositions(POSITION_TYPE_BUY, InpMagic) == 0 && l1 <= lower && c1 > lower && c1 > SC_Open(_Symbol, InpTF, 1))
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(l1 - atr * 0.2, digits);
      double slD  = ask - sl;
      if (slD <= 0) return;
      double tp   = NormalizeDouble(ask + slD * InpTP_RR, digits);
      double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Asian_BB_L");
      return;
   }

   // Short: toco banda superior
   if (SC_CountPositions(POSITION_TYPE_SELL, InpMagic) == 0 && h1 >= upper && c1 < upper && c1 < SC_Open(_Symbol, InpTF, 1))
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(h1 + atr * 0.2, digits);
      double slD  = sl - bid;
      if (slD <= 0) return;
      double tp   = NormalizeDouble(bid - slD * InpTP_RR, digits);
      double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Asian_BB_S");
   }
}
