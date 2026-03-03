//+------------------------------------------------------------------+
//|                                    GoldConsolidation_MACD.mq5     |
//| Gold M5 Consolidation Breakout with MACD Momentum - XAU/USD     |
//+------------------------------------------------------------------+
#property copyright "Gold Consolidation MACD"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Consolidation ==="
input int    InpConsolBars               = 5;       // Bars to define range (min 3-5)
input double InpMinRangePips             = 15;      // Min range height (pips, 15-20)
input double InpPipsPerPoint             = 10;      // Points per pip (XAU)

input group "=== MACD ==="
input int    InpMACD_Fast                = 12;      // Fast EMA
input int    InpMACD_Slow                = 26;      // Slow EMA
input int    InpMACD_Signal               = 9;       // Signal SMA

input group "=== Breakout Candle ==="
input double InpMinBodyRatio             = 0.5;     // Min body/range for "strong" candle

input group "=== Stop Loss & Take Profit ==="
input double InpSL_Pips                  = 19;      // SL pips from entry (18-20)
input double InpTP_Pips                  = 25;      // TP pips from entry (25-30)

input group "=== Risk ==="
input double InpRiskPercent              = 0.5;     // Risk % equity
input double InpMaxLotSize               = 0.5;     // Max lot
input double InpMinLotSize               = 0.01;    // Min lot

input group "=== Trade ==="
input int    InpMagic                    = 304004;  // Magic number

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_macdHandle = INVALID_HANDLE;

double PipsToPoints(double pips) { return pips * InpPipsPerPoint; }

bool IsNewBar()
{
   datetime t[];
   if (CopyTime(_Symbol, PERIOD_M5, 0, 1, t) < 1) return false;
   if (t[0] == g_lastBar) return false;
   g_lastBar = t[0];
   return true;
}

bool IsXAU()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

// Get consolidation range from bars [startIdx ... startIdx+count-1]. Returns rangeHigh, rangeLow, rangePips.
bool GetConsolidationRange(int startIdx, int count, double &rangeHigh, double &rangeLow, double &rangePips)
{
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(_Symbol, PERIOD_M5, startIdx, count, h) < count) return false;
   if (CopyLow(_Symbol, PERIOD_M5, startIdx, count, l) < count) return false;
   rangeHigh = h[0]; rangeLow = l[0];
   for (int i = 0; i < count; i++)
   {
      if (h[i] > rangeHigh) rangeHigh = h[i];
      if (l[i] < rangeLow) rangeLow = l[i];
   }
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return false;
   rangePips = (rangeHigh - rangeLow) / point / InpPipsPerPoint;
   return (rangeHigh > rangeLow && rangePips >= InpMinRangePips);
}

// Bar at breakIdx: closed above rangeHigh (long) or below rangeLow (short), strong candle
bool BreakoutLong(int breakIdx, double rangeHigh, double rangeLow)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M5, breakIdx, 1, o) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, breakIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M5, breakIdx, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, breakIdx, 1, l) < 1) return false;
   if (c[0] <= rangeHigh || o[0] <= rangeHigh) return false;  // body fully above resistance
   double range = h[0] - l[0];
   if (range < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return false;
   double body = c[0] - o[0];
   return (body / range >= InpMinBodyRatio);
}

bool BreakoutShort(int breakIdx, double rangeHigh, double rangeLow)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M5, breakIdx, 1, o) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, breakIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M5, breakIdx, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, breakIdx, 1, l) < 1) return false;
   if (c[0] >= rangeLow || o[0] >= rangeLow) return false;  // body fully below support
   double range = h[0] - l[0];
   if (range < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return false;
   double body = o[0] - c[0];
   return (body / range >= InpMinBodyRatio);
}

// MACD buffer 0=main, 1=signal, 2=histogram. Histogram = main - signal.
bool MACDMomentumLong(int atBar)
{
   double hist[];
   ArraySetAsSeries(hist, true);
   if (CopyBuffer(g_macdHandle, 2, atBar, 3, hist) < 3) return false;
   return (hist[1] > 0 && hist[1] > hist[2]);  // positive and increasing
}

bool MACDMomentumShort(int atBar)
{
   double hist[];
   ArraySetAsSeries(hist, true);
   if (CopyBuffer(g_macdHandle, 2, atBar, 3, hist) < 3) return false;
   return (hist[1] < 0 && hist[1] < hist[2]);  // negative and decreasing
}

double CalcLots(double slPoints, double riskPct)
{
   if (slPoints <= 0) return InpMinLotSize;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPct / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (tickVal <= 0 || tickSize <= 0 || point <= 0) return InpMinLotSize;
   double valuePerPoint = tickVal * (point / tickSize);
   double lots = riskAmount / (slPoints * valuePerPoint);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(maxL, lots));
   return MathMax(InpMinLotSize, MathMin(InpMaxLotSize, lots));
}

int CountPos(ENUM_POSITION_TYPE type)
{
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_position.SelectByIndex(i)) continue;
      if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
      if (g_position.PositionType() == type) n++;
   }
   return n;
}

int OnInit()
{
   if (!IsXAU()) { Print("Consolidation MACD: XAU/USD only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_macdHandle = iMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   if (g_macdHandle == INVALID_HANDLE) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(15);
   long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if ((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_macdHandle != INVALID_HANDLE) IndicatorRelease(g_macdHandle);
}

void OnTick()
{
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!IsNewBar()) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return;

   // Consolidation: bars 2 to 2+InpConsolBars-1 (so we have bars 2,3,...,2+InpConsolBars-1). Bar 1 = breakout candle.
   double rangeHigh, rangeLow, rangePips;
   if (!GetConsolidationRange(2, InpConsolBars, rangeHigh, rangeLow, rangePips)) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slDist = PipsToPoints(InpSL_Pips);
   double tpDist = PipsToPoints(InpTP_Pips);

   // Long: bar 1 closed above rangeHigh, strong candle, MACD histogram positive and rising. Enter at open of bar 0.
   if (BreakoutLong(1, rangeHigh, rangeLow) && MACDMomentumLong(1) && CountPos(POSITION_TYPE_BUY) == 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - slDist, digits);
      double tp = NormalizeDouble(ask + tpDist, digits);
      double slPoints = (ask - sl) / point;
      if (slPoints < 1) return;
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "ConsolMACD_L");
   }

   // Short: bar 1 closed below rangeLow, strong candle, MACD histogram negative and falling
   if (BreakoutShort(1, rangeHigh, rangeLow) && MACDMomentumShort(1) && CountPos(POSITION_TYPE_SELL) == 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(bid + slDist, digits);
      double tp = NormalizeDouble(bid - tpDist, digits);
      double slPoints = (sl - bid) / point;
      if (slPoints < 1) return;
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "ConsolMACD_S");
   }
}
