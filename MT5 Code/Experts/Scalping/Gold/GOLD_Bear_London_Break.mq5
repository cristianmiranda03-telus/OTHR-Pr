//+------------------------------------------------------------------+
//| GOLD_Bear_London_Break.mq5                                       |
//| Strategy: London Open BEARISH Breakdown Scalper                  |
//| Asset: XAUUSD | Timeframe: M15 | Session: London open 07:00 UTC  |
//| Logic: Capture the low of 05:00-07:00 UTC (pre-London range).    |
//|        At London open (07:00-08:30 UTC) sell if price breaks     |
//|        below the pre-London low with volume confirmation.        |
//| Magic: 100005                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== London Break Settings ==="
input int    InpPreSessionBars = 8;
input double InpVolMultiplier  = 1.3;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100005;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bearish: 1=loose, 2=medium, 3=strict

CTrade  g_trade;
datetime g_lastBarM15 = 0;
double   g_preLow     = 1e9;
bool     g_entryDone  = false;

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
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;

   MqlDateTime dt;
   TimeToStruct(TimeGMT() + InpUTCOffset * 3600, dt);
   int h = dt.hour;
   int m = dt.min;

   if (h == 5 && m == 0)
   {
      g_preLow    = 1e9;
      g_entryDone = false;
      double ll = SC_GetLowestLow(_Symbol, PERIOD_M15, InpPreSessionBars, 1);
      if (ll > 0) g_preLow = ll;
   }

   if (h >= 5 && h < 7)
   {
      double ll = SC_GetLowestLow(_Symbol, PERIOD_M15, InpPreSessionBars, 1);
      if (ll > 0 && ll < g_preLow) g_preLow = ll;
   }

   if (h == 7 || (h == 8 && m <= 30))
   {
      if (g_preLow >= 1e9 || g_entryDone) return;
      if (SC_TotalPositions(InpMagic) > 0) return;
      if (InpUseMTF && !SC_MTF_BearOK(_Symbol, InpMTF_MinScore)) return;

      double close  = SC_Close(_Symbol, PERIOD_M15, 1);
      double vol    = (double)SC_Volume(_Symbol, PERIOD_M15, 1);
      double avgVol = SC_AvgVolume(_Symbol, PERIOD_M15, 20, 2);
      double atr    = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
      if (atr <= 0) return;

      bool breakdown = (close < g_preLow);
      bool volOK     = (avgVol <= 0 || vol >= avgVol * InpVolMultiplier);

      if (breakdown && volOK)
      {
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
         double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
         double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
         if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Bear_London_Break"))
            g_entryDone = true;
      }
   }
}
