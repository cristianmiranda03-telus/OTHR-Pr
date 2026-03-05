//+------------------------------------------------------------------+
//| BTC_London_Open_Bear.mq5                                         |
//| Strategy: London Open BEARISH BTC Breakdown Scalper              |
//| Asset: BTCUSD | Timeframe: M15 | Session: London 07:00 UTC       |
//| Logic: EMA8 crosses below EMA21 in first London bars =           |
//|        sell the bearish momentum. Only if price closed below     |
//|        the Asian session low (confirming bearish direction).     |
//| Magic: 200012                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== London Open BTC Settings ==="
input int    InpEMA_Fast       = 8;
input int    InpEMA_Slow       = 21;
input int    InpAsianBars      = 28;
input int    InpEntryWindowMin = 90;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.3;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200012;

CTrade   g_trade;
datetime g_lastBarM15 = 0;
double   g_asianLow   = 1e9;
bool     g_entryDone  = false;

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

   MqlDateTime dt;
   TimeToStruct(TimeGMT() + InpUTCOffset * 3600, dt);
   int h = dt.hour; int m = dt.min;
   int minOfDay = h * 60 + m;

   if (h == 0 && m < 15) { g_asianLow = 1e9; g_entryDone = false; }
   if (h < 7)
   {
      double ll = SC_GetLowestLow(_Symbol, PERIOD_M15, InpAsianBars, 1);
      if (ll > 0 && ll < g_asianLow) g_asianLow = ll;
      return;
   }
   if (minOfDay < 7 * 60 || minOfDay > 7 * 60 + InpEntryWindowMin) return;
   if (g_entryDone || SC_TotalPositions(InpMagic) > 0) return;

   double ema8  = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Fast, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Slow, 1);
   double ema8p = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Fast, 2);
   double ema21p= SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Slow, 2);
   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0) return;

   bool emaCross    = (ema8 < ema21 && ema8p >= ema21p);
   bool belowAsian  = (g_asianLow >= 1e9 || close < g_asianLow);

   if (emaCross && belowAsian)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_London_Open_Bear"))
         g_entryDone = true;
   }
}
