//+------------------------------------------------------------------+
//| GOLD_Asian_Range_Breakout.mq5                                    |
//| Strategy: Asian Session Range Breakout (Both Directions)         |
//| Asset: XAUUSD | Timeframe: M15 | Session: London open            |
//| Logic: Calculate Tokyo/Asian session range (00:00-07:00 UTC).    |
//|        At London open (07:00 UTC+) trade the break of that range.|
//|        Direction determined by which side breaks first.          |
//| Magic: 100008                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Asian Range Settings ==="
input int    InpAsianBars      = 28;    // M15 bars in Asian session (7h = 28 bars)
input double InpBreakBuffer    = 0.2;   // ATR buffer above/below range to confirm break
input int    InpEntryWindowMin = 120;  // Entry window after London open (minutes)

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_RR          = 2.5;  // Risk:Reward ratio
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100008;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min score to take a directional trade (1-3)

CTrade   g_trade;
datetime g_lastBarM15 = 0;
double   g_asianHigh  = 0;
double   g_asianLow   = 1e9;
bool     g_bullDone   = false;
bool     g_bearDone   = false;

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
   int h = dt.hour; int m = dt.min;
   int minOfDay = h * 60 + m;

   // Reset and build Asian range 00:00-07:00 UTC
   if (h == 0 && m < 15)
   {
      g_asianHigh = 0;
      g_asianLow  = 1e9;
      g_bullDone  = false;
      g_bearDone  = false;
   }
   if (h < 7)
   {
      double hh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpAsianBars, 1);
      double ll = SC_GetLowestLow(_Symbol, PERIOD_M15, InpAsianBars, 1);
      if (hh > g_asianHigh) g_asianHigh = hh;
      if (ll > 0 && ll < g_asianLow) g_asianLow = ll;
      return;
   }

   // Entry: 07:00 to 09:00 UTC
   if (minOfDay < 7 * 60 || minOfDay > 7 * 60 + InpEntryWindowMin) return;
   if (g_asianHigh <= 0 || g_asianLow >= 1e9) return;
   int g_mtfScore = InpUseMTF ? SC_MTF_Score(_Symbol) : 0;

   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0) return;

   double buf = atr * InpBreakBuffer;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Bullish break
   if (!g_bullDone && SC_CountPositions(POSITION_TYPE_BUY, InpMagic) == 0
       && close > g_asianHigh + buf && g_mtfScore >= -InpMTF_MinScore)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(g_asianHigh - atr * InpSL_ATR_Mult, digits);
      double slD  = ask - sl;
      double tp   = NormalizeDouble(ask + slD * InpTP_RR, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Asian_Bull_Break"))
         g_bullDone = true;
   }
   // Bearish break
   if (!g_bearDone && SC_CountPositions(POSITION_TYPE_SELL, InpMagic) == 0
       && close < g_asianLow - buf && g_mtfScore <= InpMTF_MinScore)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(g_asianLow + atr * InpSL_ATR_Mult, digits);
      double slD  = sl - bid;
      double tp   = NormalizeDouble(bid - slD * InpTP_RR, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Asian_Bear_Break"))
         g_bearDone = true;
   }
}
