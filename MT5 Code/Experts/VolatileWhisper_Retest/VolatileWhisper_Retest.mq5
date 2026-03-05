//+------------------------------------------------------------------+
//|                                  VolatileWhisper_Retest.mq5      |
//| Volatile Whisper Retest - XAUUSD 1-2 min, NY Session             |
//+------------------------------------------------------------------+
#property copyright "Volatile Whisper Retest"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Timeframe & Session ==="
input ENUM_TIMEFRAMES InpTF             = PERIOD_M1;
input int    InpNY_StartHour            = 14;
input int    InpNY_EndHour              = 21;

input group "=== Micro-Structure & Breakout ==="
input int    InpConsolBars              = 10;         // Consolidation lookback (5-15)
input double InpBreakout_BodyPct        = 0.70;       // Breakout body > 70% of range

input group "=== Volatile Whisper (ATR) ==="
input int    InpATR_Period              = 5;
input int    InpATR_SMA_Period          = 20;         // SMA(ATR,20) baseline
input double InpRetest_BodyPct          = 0.30;       // Retest candle body < 30% avg body
input double InpRetest_WickPct           = 0.50;       // Wicks < 50% of body

input group "=== Rejection Candle ==="
input double InpReject_BodyPct          = 0.50;       // Strong body or engulfing

input group "=== Stop & Target ==="
input double InpSL_ATRBuffer            = 0.5;        // SL beyond rejection + ATR buffer
input double InpTP_MinRR                = 1.5;        // Min TP = 1.5 * risk
input double InpTrail_ATRBuffer         = 0.5;        // Trail buffer (ATR)
input int    InpTrail_Bars              = 3;          // Trail behind last N bars

input group "=== Profit Protection Exit ==="
input double InpExhaust_ATRSpikePct     = 1.50;       // ATR > baseline by 50% = exit
input int    InpExhaust_ConsecCandles   = 3;          // Decreasing bodies = exhaustion
input double InpExhaust_MinR            = 1.0;         // Min profit (R) to trigger

input group "=== Risk ==="
input double InpRiskPercent             = 0.5;
input double InpMaxLotSize              = 0.5;
input double InpMinLotSize              = 0.01;
input int    InpMagic                   = 402002;

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_atrHandle = INVALID_HANDLE;

bool IsNewBar() { datetime t[]; ArraySetAsSeries(t, true); if (CopyTime(_Symbol, InpTF, 0, 1, t) < 1) return false; if (t[0] == g_lastBar) return false; g_lastBar = t[0]; return true; }
bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InNYSession() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); if (InpNY_EndHour > InpNY_StartHour) return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour); return (dt.hour >= InpNY_StartHour || dt.hour < InpNY_EndHour); }

double GetATR(int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(g_atrHandle, 0, shift, 1, b) < 1) return 0; return b[0]; }
double GetATRBaseline(int shift) {
   double b[]; ArraySetAsSeries(b, true);
   if (CopyBuffer(g_atrHandle, 0, shift, InpATR_SMA_Period, b) < InpATR_SMA_Period) return 0;
   double sum = 0; for (int i = 0; i < InpATR_SMA_Period; i++) sum += b[i]; return sum / (double)InpATR_SMA_Period;
}

bool GetConsolidationRange(int startBar, int count, double &rangeHigh, double &rangeLow) {
   double h[], l[]; ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(_Symbol, InpTF, startBar, count, h) < count || CopyLow(_Symbol, InpTF, startBar, count, l) < count) return false;
   rangeHigh = h[0]; rangeLow = l[0];
   for (int i = 0; i < count; i++) { if (h[i] > rangeHigh) rangeHigh = h[i]; if (l[i] < rangeLow) rangeLow = l[i]; }
   return (rangeHigh > rangeLow);
}

double AvgBodySize(int fromBar, int count) {
   double o[], c[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, fromBar, count, o) < count || CopyClose(_Symbol, InpTF, fromBar, count, c) < count) return 0;
   double sum = 0; for (int i = 0; i < count; i++) sum += MathAbs(c[i] - o[i]); return sum / (double)count;
}

bool BreakoutLong(int barIdx, double rangeHigh) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] <= rangeHigh) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   return (MathAbs(c[0] - o[0]) / range >= InpBreakout_BodyPct);
}

bool BreakoutShort(int barIdx, double rangeLow) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] >= rangeLow) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   return (MathAbs(c[0] - o[0]) / range >= InpBreakout_BodyPct);
}

bool RetestTouchLong(double level, int barIdx) {
   double h[], l[]; ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5;
   return (l[0] <= level + point && h[0] >= level - point);
}

bool RetestTouchShort(double level, int barIdx) {
   double h[], l[]; ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5;
   return (h[0] >= level - point && l[0] <= level + point);
}

bool LowVolatilityRetestCandle(int barIdx, double avgBody) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double body = MathAbs(c[0] - o[0]); double range = h[0] - l[0];
   if (range < 1e-9) return true;
   if (avgBody > 1e-9 && body > InpRetest_BodyPct * avgBody) return false;
   double lowerWick = MathMin(o[0], c[0]) - l[0], upperWick = h[0] - MathMax(o[0], c[0]);
   if (body > 1e-9 && (lowerWick > InpRetest_WickPct * body || upperWick > InpRetest_WickPct * body)) return false;
   return true;
}

bool RejectionCandleLong(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] <= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double lowerWick = MathMin(o[0], c[0]) - l[0];
   if (lowerWick < range * 0.5) return false;
   return ((c[0] - o[0]) / range >= InpReject_BodyPct || (c[0] - l[0]) >= range * 0.5);
}

bool RejectionCandleShort(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] >= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double upperWick = h[0] - MathMax(o[0], c[0]);
   if (upperWick < range * 0.5) return false;
   return ((o[0] - c[0]) / range >= InpReject_BodyPct || (h[0] - c[0]) >= range * 0.5);
}

bool ExhaustionOrSpikeExit(bool isLong, double entryPrice, double initialSL) {
   double atr = GetATR(1), baseline = GetATRBaseline(1);
   if (baseline > 1e-9 && atr >= baseline * InpExhaust_ATRSpikePct) return true;
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, 1, InpExhaust_ConsecCandles + 2, o) < InpExhaust_ConsecCandles + 2) return false;
   if (CopyClose(_Symbol, InpTF, 1, InpExhaust_ConsecCandles + 2, c) < InpExhaust_ConsecCandles + 2) return false;
   double risk = MathAbs(entryPrice - initialSL);
   double profit = isLong ? (SymbolInfoDouble(_Symbol, SYMBOL_BID) - entryPrice) : (entryPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   if (profit < InpExhaust_MinR * risk) return false;
   int dec = 0;
   for (int i = 0; i < InpExhaust_ConsecCandles; i++) {
      double body = MathAbs(c[i] - o[i]);
      if (i > 0 && body < MathAbs(c[i-1] - o[i-1])) dec++;
   }
   return (dec >= InpExhaust_ConsecCandles - 1);
}

double CalcLots(double slDist, double riskPct) {
   if (slDist <= 0) return InpMinLotSize;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPoints = slDist / point;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPct / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickVal <= 0 || tickSize <= 0 || point <= 0) return InpMinLotSize;
   double valuePerPoint = tickVal * (point / tickSize);
   double lots = riskAmount / (slPoints * valuePerPoint);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lots));
   return MathMax(InpMinLotSize, MathMin(InpMaxLotSize, lots));
}

int PositionCount() {
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!g_position.SelectByIndex(i)) continue;
      if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
      n++;
   }
   return n;
}

int OnInit() {
   if (!IsXAU()) { Print("Volatile Whisper: XAU only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_atrHandle = iATR(_Symbol, InpTF, InpATR_Period);
   if (g_atrHandle == INVALID_HANDLE) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if ((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { if (g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle); }

void OnTick() {
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!InNYSession()) return;
   if (PositionCount() > 0) {
      for (int i = PositionsTotal() - 1; i >= 0; i--) {
         if (!g_position.SelectByIndex(i)) continue;
         if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
         bool isLong = (g_position.PositionType() == POSITION_TYPE_BUY);
         double entryPrice = g_position.PriceOpen();
         double posSL = g_position.StopLoss();
         double posTP = g_position.TakeProfit();
         double risk = MathAbs(entryPrice - (isLong ? posSL : (posSL > 0 ? posSL : entryPrice + 0.5)));
         if (posSL > 0) risk = MathAbs(entryPrice - posSL);
         if (ExhaustionOrSpikeExit(isLong, entryPrice, entryPrice - (isLong ? risk : -risk))) { g_trade.PositionClose(g_position.Ticket()); return; }
      }
      return;
   }
   if (!IsNewBar()) return;

   double rangeHigh, rangeLow;
   if (!GetConsolidationRange(InpConsolBars + 5, InpConsolBars, rangeHigh, rangeLow)) return;

   double atrNow = GetATR(1), baseline = GetATRBaseline(1);
   if (baseline <= 0 || atrNow >= baseline) return;

   double avgBody = AvgBodySize(2, 10);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for (int b = 2; b <= 5; b++) {
      if (!BreakoutLong(b + 1, rangeHigh)) continue;
      double retestLevel = rangeHigh;
      bool foundRetest = false;
      int rejectBar = -1;
      for (int r = b; r >= 1; r--) {
         if (!RetestTouchLong(retestLevel, r)) continue;
         if (GetATRBaseline(r) > 0 && GetATR(r) >= GetATRBaseline(r)) break;
         if (!LowVolatilityRetestCandle(r, avgBody)) continue;
         if (r >= 1 && RejectionCandleLong(r - 1)) { foundRetest = true; rejectBar = r - 1; break; }
         if (RejectionCandleLong(r)) { foundRetest = true; rejectBar = r; break; }
      }
      if (!foundRetest || rejectBar < 0) continue;
      double rejL[], rejH[]; ArraySetAsSeries(rejL, true); ArraySetAsSeries(rejH, true);
      if (CopyLow(_Symbol, InpTF, rejectBar, 1, rejL) < 1 || CopyHigh(_Symbol, InpTF, rejectBar, 1, rejH) < 1) continue;
      double sl = NormalizeDouble(rejL[0] - GetATR(rejectBar + 1) * InpSL_ATRBuffer, d);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskDist = ask - sl;
      if (riskDist <= 0) continue;
      double tp = NormalizeDouble(ask + riskDist * InpTP_MinRR, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Buy(lots, _Symbol, ask, sl, tp, "VW_L");
      return;
   }

   for (int b = 2; b <= 5; b++) {
      if (!BreakoutShort(b + 1, rangeLow)) continue;
      double retestLevel = rangeLow;
      bool foundRetest = false;
      int rejectBar = -1;
      for (int r = b; r >= 1; r--) {
         if (!RetestTouchShort(retestLevel, r)) continue;
         if (GetATRBaseline(r) > 0 && GetATR(r) >= GetATRBaseline(r)) break;
         if (!LowVolatilityRetestCandle(r, avgBody)) continue;
         if (r >= 1 && RejectionCandleShort(r - 1)) { foundRetest = true; rejectBar = r - 1; break; }
         if (RejectionCandleShort(r)) { foundRetest = true; rejectBar = r; break; }
      }
      if (!foundRetest || rejectBar < 0) continue;
      double rejL[], rejH[]; ArraySetAsSeries(rejL, true); ArraySetAsSeries(rejH, true);
      if (CopyLow(_Symbol, InpTF, rejectBar, 1, rejL) < 1 || CopyHigh(_Symbol, InpTF, rejectBar, 1, rejH) < 1) continue;
      double sl = NormalizeDouble(rejH[0] + GetATR(rejectBar + 1) * InpSL_ATRBuffer, d);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double riskDist = sl - bid;
      if (riskDist <= 0) continue;
      double tp = NormalizeDouble(bid - riskDist * InpTP_MinRR, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Sell(lots, _Symbol, bid, sl, tp, "VW_S");
      return;
   }
}
