//+------------------------------------------------------------------+
//| GOLD_Bull_London_Break.mq5                                       |
//| Strategy: London Open BULLISH Breakout Scalper                   |
//| Asset: XAUUSD | Timeframe: M15 | Session: London open 07:00 UTC  |
//| Logic: Capture the high of 05:00-07:00 UTC (pre-London range).   |
//|        At London open (07:00-08:30 UTC) buy if price breaks      |
//|        above the pre-London high with volume confirmation.       |
//| Magic: 100004                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== London Break Settings ==="
input int    InpPreSessionBars = 8;      // M15 bars for pre-London range (8 x 15min = 2h)
input int    InpEntryWindowMin = 90;     // Entry window after London open (minutes)
input double InpVolMultiplier  = 1.3;   // Volume > N x avg to confirm break

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
input int    InpMagic          = 100004;

CTrade  g_trade;
datetime g_lastBarM15 = 0;
double   g_preHigh    = 0;
bool     g_entryDone  = false;
datetime g_londonOpen = 0;

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

   // Reset daily at 05:00 UTC
   if (h == 5 && m == 0)
   {
      g_preHigh   = 0;
      g_entryDone = false;
      // Calculate pre-London high over last InpPreSessionBars M15 bars
      g_preHigh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpPreSessionBars, 1);
      g_londonOpen = (datetime)(TimeCurrent() + (7 - h) * 3600);
   }

   // Update pre-London high during 05:00-07:00 UTC
   if (h >= 5 && h < 7)
   {
      double hh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpPreSessionBars, 1);
      if (hh > g_preHigh) g_preHigh = hh;
   }

   // Entry window: 07:00-08:30 UTC
   if (h == 7 || (h == 8 && m <= 30))
   {
      if (g_preHigh <= 0 || g_entryDone) return;
      if (SC_TotalPositions(InpMagic) > 0) return;

      double close  = SC_Close(_Symbol, PERIOD_M15, 1);
      double vol    = (double)SC_Volume(_Symbol, PERIOD_M15, 1);
      double avgVol = SC_AvgVolume(_Symbol, PERIOD_M15, 20, 2);
      double atr    = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
      if (atr <= 0) return;

      bool breakout  = (close > g_preHigh);
      bool volOK     = (avgVol <= 0 || vol >= avgVol * InpVolMultiplier);

      if (breakout && volOK)
      {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
         double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
         double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
         if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Bull_London_Break"))
            g_entryDone = true;
      }
   }
}
