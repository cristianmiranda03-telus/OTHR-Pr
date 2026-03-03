//+------------------------------------------------------------------+
//|                                    GoldMomentum_Scalper.mq5      |
//| Gold Momentum Scalper - 50 EMA + Stochastic 14,3,3 - XAU M5     |
//+------------------------------------------------------------------+
#property copyright "Gold Momentum Scalper"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== EMA Trend ==="
input int    InpEMA_Period               = 50;      // EMA period

input group "=== Stochastic ==="
input int    InpStoch_K                  = 14;      // %K period
input int    InpStoch_D                  = 3;       // %D period
input int    InpStoch_Slowing            = 3;       // Slowing
input double InpStoch_Oversold          = 20;      // Oversold level (below = long zone)
input double InpStoch_Overbought        = 80;      // Overbought level (above = short zone)

input group "=== Stop Loss ==="
input double InpSL_PipsBelowLow          = 8;       // SL pips below signal candle low (long)
input double InpSL_PipsAboveHigh         = 8;       // SL pips above signal candle high (short)
input double InpSL_MaxPips               = 15;      // Max SL width (else use fixed 10 pips)
input double InpSL_FixedPips             = 10;      // Fixed SL pips when candle too wide
input double InpPipsPerPoint             = 10;      // Points per pip (XAU)

input group "=== Take Profit ==="
input double InpTP_Pips                  = 18;      // Fixed TP pips (15-20)
input double InpTP_RR_Min                 = 1.5;     // Or min R:R (1:1.5)

input group "=== Risk ==="
input double InpRiskPercent              = 0.5;     // Risk % equity
input double InpMaxLotSize               = 0.5;     // Max lot
input double InpMinLotSize               = 0.01;    // Min lot

input group "=== Trade ==="
input int    InpMagic                    = 303003;  // Magic number

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_emaHandle = INVALID_HANDLE;
int            g_stochHandle = INVALID_HANDLE;

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

double GetEMA(int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_emaHandle, 0, shift, 1, buf) < 1) return 0;
   return buf[0];
}

// Stochastic: buffer 0 = main line (%K), buffer 1 = signal (%D)
bool StochCrossUpOversold(int signalBar)
{
   double k[], d[];
   ArraySetAsSeries(k, true); ArraySetAsSeries(d, true);
   if (CopyBuffer(g_stochHandle, 0, signalBar, 3, k) < 3) return false;
   if (CopyBuffer(g_stochHandle, 1, signalBar, 3, d) < 3) return false;
   if (k[1] <= d[1]) return false;   // at signal bar K must be above D
   if (k[2] >= d[2]) return false;   // previous bar K was below D (crossover)
   if (k[1] >= InpStoch_Oversold || d[1] >= InpStoch_Oversold) return false;
   return true;
}

bool StochCrossDownOverbought(int signalBar)
{
   double k[], d[];
   ArraySetAsSeries(k, true); ArraySetAsSeries(d, true);
   if (CopyBuffer(g_stochHandle, 0, signalBar, 3, k) < 3) return false;
   if (CopyBuffer(g_stochHandle, 1, signalBar, 3, d) < 3) return false;
   if (k[1] >= d[1]) return false;
   if (k[2] <= d[2]) return false;
   if (k[1] <= InpStoch_Overbought || d[1] <= InpStoch_Overbought) return false;
   return true;
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
   if (!IsXAU()) { Print("Gold Momentum Scalper: XAU/USD only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_emaHandle = iMA(_Symbol, PERIOD_M5, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_stochHandle = iStochastic(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
   if (g_emaHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE) return INIT_FAILED;
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
   if (g_emaHandle != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   if (g_stochHandle != INVALID_HANDLE) IndicatorRelease(g_stochHandle);
}

void OnTick()
{
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!IsNewBar()) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return;

   double c[], l[], h[], ema1;
   ArraySetAsSeries(c, true); ArraySetAsSeries(l, true); ArraySetAsSeries(h, true);
   if (CopyClose(_Symbol, PERIOD_M5, 1, 1, c) < 1) return;
   if (CopyLow(_Symbol, PERIOD_M5, 1, 1, l) < 1) return;
   if (CopyHigh(_Symbol, PERIOD_M5, 1, 1, h) < 1) return;
   ema1 = GetEMA(1);
   if (ema1 <= 0) return;

   // Long: bar 1 was signal (K cross above D, both < 20), close[1] > EMA. Enter at bar 0 open (current).
   if (StochCrossUpOversold(1) && c[0] > ema1 && CountPos(POSITION_TYPE_BUY) == 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = PipsToPoints(InpSL_PipsBelowLow);
      double sl = NormalizeDouble(l[0] - slDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double slPipsFromEntry = (ask - sl) / point / InpPipsPerPoint;
      if (slPipsFromEntry > InpSL_MaxPips)
         sl = NormalizeDouble(ask - PipsToPoints(InpSL_FixedPips), (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double slPoints = (ask - sl) / point;
      if (slPoints < 1) return;
      double tpDist = MathMax(PipsToPoints(InpTP_Pips), (ask - sl) * InpTP_RR_Min);
      double tp = NormalizeDouble(ask + tpDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "Momentum_L");
   }

   // Short: bar 1 was signal (K cross below D, both > 80), close[1] < EMA
   if (StochCrossDownOverbought(1) && c[0] < ema1 && CountPos(POSITION_TYPE_SELL) == 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slDist = PipsToPoints(InpSL_PipsAboveHigh);
      double sl = NormalizeDouble(h[0] + slDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double slPipsFromEntry = (sl - bid) / point / InpPipsPerPoint;
      if (slPipsFromEntry > InpSL_MaxPips)
         sl = NormalizeDouble(bid + PipsToPoints(InpSL_FixedPips), (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double slPoints = (sl - bid) / point;
      if (slPoints < 1) return;
      double tpDist = MathMax(PipsToPoints(InpTP_Pips), (sl - bid) * InpTP_RR_Min);
      double tp = NormalizeDouble(bid - tpDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double lots = CalcLots(slPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "Momentum_S");
   }
}
