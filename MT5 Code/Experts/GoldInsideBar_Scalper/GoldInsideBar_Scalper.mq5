//+------------------------------------------------------------------+
//|                                    GoldInsideBar_Scalper.mq5      |
//| XAU/USD M5 Inside Bar Breakout with SMA 20 trend filter         |
//+------------------------------------------------------------------+
#property copyright "Gold Inside Bar Scalper"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== SMA Trend Filter ==="
input int    InpSMA_Period               = 20;      // SMA period

input group "=== Stop Loss ==="
input double InpSL_BufferPoints          = 15;      // SL buffer below/above Mother Bar (points, 10-20 for XAU)

input group "=== Take Profit ==="
input double InpTP_RR_Mult               = 1.5;     // TP = Mother Bar range * this (1:1.5 RRR)

input group "=== Risk ==="
input double InpRiskPercent              = 0.5;     // Risk % equity
input double InpMaxLotSize               = 0.5;     // Max lot
input double InpMinLotSize               = 0.01;    // Min lot

input group "=== Trade ==="
input int    InpMagic                    = 302002;  // Magic number

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_smaHandle = INVALID_HANDLE;

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

double GetSMA(int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_smaHandle, 0, shift, 1, buf) < 1) return 0;
   return buf[0];
}

// Bar at shift 2 = Inside bar, Bar at shift 3 = Mother bar
// Inside: high < Mother high, low > Mother low
bool IsInsideBar(int insideShift, int motherShift)
{
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(_Symbol, PERIOD_M5, insideShift, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, insideShift, 1, l) < 1) return false;
   double hM[], lM[];
   ArraySetAsSeries(hM, true); ArraySetAsSeries(lM, true);
   if (CopyHigh(_Symbol, PERIOD_M5, motherShift, 1, hM) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, motherShift, 1, lM) < 1) return false;
   return (h[0] < hM[0] && l[0] > lM[0]);
}

// Breakout candle (bar 1) closed above mother high (long) or below mother low (short)
bool BreakoutLong(int breakoutShift, int motherShift)
{
   double c[];
   ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, PERIOD_M5, breakoutShift, 1, c) < 1) return false;
   double hM[];
   ArraySetAsSeries(hM, true);
   if (CopyHigh(_Symbol, PERIOD_M5, motherShift, 1, hM) < 1) return false;
   return (c[0] > hM[0]);
}

bool BreakoutShort(int breakoutShift, int motherShift)
{
   double c[];
   ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, PERIOD_M5, breakoutShift, 1, c) < 1) return false;
   double lM[];
   ArraySetAsSeries(lM, true);
   if (CopyLow(_Symbol, PERIOD_M5, motherShift, 1, lM) < 1) return false;
   return (c[0] < lM[0]);
}

// Mother and Inside both closed above SMA (long) or below (short)
bool TrendFilterLong(int insideShift, int motherShift)
{
   double cIn[], cMo[];
   ArraySetAsSeries(cIn, true); ArraySetAsSeries(cMo, true);
   if (CopyClose(_Symbol, PERIOD_M5, insideShift, 1, cIn) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, motherShift, 1, cMo) < 1) return false;
   double smaIn = GetSMA(insideShift), smaMo = GetSMA(motherShift);
   return (smaIn > 0 && smaMo > 0 && cIn[0] > smaIn && cMo[0] > smaMo);
}

bool TrendFilterShort(int insideShift, int motherShift)
{
   double cIn[], cMo[];
   ArraySetAsSeries(cIn, true); ArraySetAsSeries(cMo, true);
   if (CopyClose(_Symbol, PERIOD_M5, insideShift, 1, cIn) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, motherShift, 1, cMo) < 1) return false;
   double smaIn = GetSMA(insideShift), smaMo = GetSMA(motherShift);
   return (smaIn > 0 && smaMo > 0 && cIn[0] < smaIn && cMo[0] < smaMo);
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
   if (!IsXAU()) { Print("Inside Bar Scalper: XAU/USD only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_smaHandle = iMA(_Symbol, PERIOD_M5, InpSMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if (g_smaHandle == INVALID_HANDLE) return INIT_FAILED;
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
   if (g_smaHandle != INVALID_HANDLE) IndicatorRelease(g_smaHandle);
}

void OnTick()
{
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!IsNewBar()) return;

   // Bar 1 = breakout candle (just closed), Bar 2 = inside, Bar 3 = mother
   if (!IsInsideBar(2, 3)) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return;

   double hMother[], lMother[];
   ArraySetAsSeries(hMother, true); ArraySetAsSeries(lMother, true);
   if (CopyHigh(_Symbol, PERIOD_M5, 3, 1, hMother) < 1 || CopyLow(_Symbol, PERIOD_M5, 3, 1, lMother) < 1) return;
   double motherRange = hMother[0] - lMother[0];
   if (motherRange <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Long: trend filter + breakout above mother high
   if (TrendFilterLong(2, 3) && BreakoutLong(1, 3) && CountPos(POSITION_TYPE_BUY) == 0)
   {
      double sl = NormalizeDouble(lMother[0] - InpSL_BufferPoints * point, digits);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slPoints = (ask - sl) / point;
      if (slPoints < 1) return;
      double tpDist = motherRange * InpTP_RR_Mult;
      double tp = NormalizeDouble(ask + tpDist, digits);
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "InsideBar_L");
   }

   // Short: trend filter + breakout below mother low
   if (TrendFilterShort(2, 3) && BreakoutShort(1, 3) && CountPos(POSITION_TYPE_SELL) == 0)
   {
      double sl = NormalizeDouble(hMother[0] + InpSL_BufferPoints * point, digits);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slPoints = (sl - bid) / point;
      if (slPoints < 1) return;
      double tpDist = motherRange * InpTP_RR_Mult;
      double tp = NormalizeDouble(bid - tpDist, digits);
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "InsideBar_S");
   }
}
