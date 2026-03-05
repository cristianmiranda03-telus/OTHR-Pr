//+------------------------------------------------------------------+
//|                        AdaptiveSqueeze_MomentumBurst.mq5         |
//| NY Session Adaptive Volatility Squeeze & Momentum Burst - XAUUSD |
//+------------------------------------------------------------------+
#property copyright "Adaptive Squeeze Momentum Burst"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Session ==="
input int    InpNY_StartHour            = 13;
input int    InpNY_EndHour              = 22;         // 5 PM EST

input group "=== Keltner (Inner = Squeeze) ==="
input int    InpInner_Period            = 20;
input double InpInner_ATRMult            = 1.5;
input int    InpATR_Period              = 14;

input group "=== Keltner (Outer = TP target) ==="
input int    InpOuter_Period            = 40;
input double InpOuter_ATRMult            = 2.5;

input group "=== Squeeze ==="
input int    InpSqueezeBars             = 5;          // Price inside Inner for N bars
input bool   InpRequireInnerInOuter      = true;       // Inner bands inside Outer

input group "=== Breakout Candle ==="
input double InpTrigger_BodyVsSqueeze   = 1.5;        // Body >= 1.5 * avg squeeze body

input group "=== Fast Momentum (Stochastic) ==="
input int    InpStoch_K                 = 5;
input int    InpStoch_D                 = 3;
input int    InpStoch_Slowing           = 3;

input group "=== Stop & Target ==="
input double InpTP_RR_Min               = 1.5;
input double InpTP_RR_Max               = 2.5;
input bool   InpUseOuterAsTP            = true;       // TP = Outer band
input double InpBE_TriggerR             = 1.0;

input group "=== Risk ==="
input double InpRiskPercent             = 0.5;
input double InpMaxLotSize              = 0.5;
input double InpMinLotSize              = 0.01;
input int    InpMagic                   = 404004;

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_atrHandle = INVALID_HANDLE;
int            g_emaInnerHandle = INVALID_HANDLE;
int            g_emaOuterHandle = INVALID_HANDLE;
int            g_stochHandle = INVALID_HANDLE;

ENUM_TIMEFRAMES InpTF = PERIOD_M1;

bool IsNewBar() { datetime t[]; ArraySetAsSeries(t, true); if (CopyTime(_Symbol, InpTF, 0, 1, t) < 1) return false; if (t[0] == g_lastBar) return false; g_lastBar = t[0]; return true; }
bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InNYSession() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); if (InpNY_EndHour > InpNY_StartHour) return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour); return (dt.hour >= InpNY_StartHour || dt.hour < InpNY_EndHour); }

double GetATR(int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(g_atrHandle, 0, shift, 1, b) < 1) return 0; return b[0]; }
double GetEMA(int handle, int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(handle, 0, shift, 1, b) < 1) return 0; return b[0]; }
void KeltnerBands(int shift, double &upper, double &lower, int period, double atrMult) {
   double ema[]; ArraySetAsSeries(ema, true);
   int h = (period == InpInner_Period) ? g_emaInnerHandle : g_emaOuterHandle;
   if (CopyBuffer(h, 0, shift, 1, ema) < 1) { upper = 0; lower = 0; return; }
   double atr = GetATR(shift);
   upper = ema[0] + atr * atrMult; lower = ema[0] - atr * atrMult;
}

bool SqueezeConfirmed(int atBar) {
   double iUp, iLo, oUp, oLo;
   KeltnerBands(atBar, iUp, iLo, InpInner_Period, InpInner_ATRMult);
   KeltnerBands(atBar, oUp, oLo, InpOuter_Period, InpOuter_ATRMult);
   if (iUp <= 0 || oUp <= 0) return false;
   if (InpRequireInnerInOuter && (iUp >= oUp || iLo <= oLo)) return false;
   double c[]; ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, InpTF, atBar, InpSqueezeBars, c) < InpSqueezeBars) return false;
   for (int i = 0; i < InpSqueezeBars; i++) {
      double iU, iL; KeltnerBands(atBar + i, iU, iL, InpInner_Period, InpInner_ATRMult);
      if (c[i] > iU || c[i] < iL) return false;
   }
   return true;
}

double AvgSqueezeBody(int atBar, int count) {
   double o[], c[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, atBar, count, o) < count || CopyClose(_Symbol, InpTF, atBar, count, c) < count) return 0;
   double sum = 0; for (int i = 0; i < count; i++) sum += MathAbs(c[i] - o[i]); return sum / (double)count;
}

bool BreakoutLongCandle(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double iUp, iLo; KeltnerBands(barIdx + 1, iUp, iLo, InpInner_Period, InpInner_ATRMult);
   if (c[0] <= iUp) return false;
   double body = c[0] - o[0]; if (body <= 0) return false;
   double avgBody = AvgSqueezeBody(barIdx + 2, InpSqueezeBars);
   return (avgBody > 0 && body >= InpTrigger_BodyVsSqueeze * avgBody);
}

bool BreakoutShortCandle(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double iUp, iLo; KeltnerBands(barIdx + 1, iUp, iLo, InpInner_Period, InpInner_ATRMult);
   if (c[0] >= iLo) return false;
   double body = o[0] - c[0]; if (body <= 0) return false;
   double avgBody = AvgSqueezeBody(barIdx + 2, InpSqueezeBars);
   return (avgBody > 0 && body >= InpTrigger_BodyVsSqueeze * avgBody);
}

bool StochCrossUp(int barIdx) {
   double k[], d[]; ArraySetAsSeries(k, true); ArraySetAsSeries(d, true);
   if (CopyBuffer(g_stochHandle, 0, barIdx, 3, k) < 3 || CopyBuffer(g_stochHandle, 1, barIdx, 3, d) < 3) return false;
   return (k[1] > d[1] && k[2] <= d[2]);
}
bool StochCrossDown(int barIdx) {
   double k[], d[]; ArraySetAsSeries(k, true); ArraySetAsSeries(d, true);
   if (CopyBuffer(g_stochHandle, 0, barIdx, 3, k) < 3 || CopyBuffer(g_stochHandle, 1, barIdx, 3, d) < 3) return false;
   return (k[1] < d[1] && k[2] >= d[2]);
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

int PositionCount() { int n = 0; for (int i = PositionsTotal() - 1; i >= 0; i--) { if (!g_position.SelectByIndex(i)) continue; if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue; n++; } return n; }

int OnInit() {
   if (!IsXAU()) { Print("Adaptive Squeeze: XAU only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_atrHandle = iATR(_Symbol, InpTF, InpATR_Period);
   g_emaInnerHandle = iMA(_Symbol, InpTF, InpInner_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_emaOuterHandle = iMA(_Symbol, InpTF, InpOuter_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_stochHandle = iStochastic(_Symbol, InpTF, InpStoch_K, InpStoch_D, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
   if (g_atrHandle == INVALID_HANDLE || g_emaInnerHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if ((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if (g_emaInnerHandle != INVALID_HANDLE) IndicatorRelease(g_emaInnerHandle);
   if (g_emaOuterHandle != INVALID_HANDLE) IndicatorRelease(g_emaOuterHandle);
   if (g_stochHandle != INVALID_HANDLE) IndicatorRelease(g_stochHandle);
}

void OnTick() {
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!InNYSession()) return;
   if (PositionCount() > 0) return;
   if (!IsNewBar()) return;

   if (!SqueezeConfirmed(2)) return;

   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (BreakoutLongCandle(1) && StochCrossUp(1)) {
      double l[]; ArraySetAsSeries(l, true);
      if (CopyLow(_Symbol, InpTF, 1, 1, l) < 1) return;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(l[0], d);
      double riskDist = ask - sl;
      if (riskDist <= 0) return;
      double oUp, oLo; KeltnerBands(1, oUp, oLo, InpOuter_Period, InpOuter_ATRMult);
      double tp = InpUseOuterAsTP ? NormalizeDouble(oUp, d) : NormalizeDouble(ask + riskDist * ((InpTP_RR_Min + InpTP_RR_Max) / 2.0), d);
      if (tp <= ask) tp = NormalizeDouble(ask + riskDist * InpTP_RR_Min, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Buy(lots, _Symbol, ask, sl, tp, "Sqz_L");
      return;
   }
   if (BreakoutShortCandle(1) && StochCrossDown(1)) {
      double h[]; ArraySetAsSeries(h, true);
      if (CopyHigh(_Symbol, InpTF, 1, 1, h) < 1) return;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(h[0], d);
      double riskDist = sl - bid;
      if (riskDist <= 0) return;
      double oUp, oLo; KeltnerBands(1, oUp, oLo, InpOuter_Period, InpOuter_ATRMult);
      double tp = InpUseOuterAsTP ? NormalizeDouble(oLo, d) : NormalizeDouble(bid - riskDist * ((InpTP_RR_Min + InpTP_RR_Max) / 2.0), d);
      if (tp >= bid) tp = NormalizeDouble(bid - riskDist * InpTP_RR_Min, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Sell(lots, _Symbol, bid, sl, tp, "Sqz_S");
   }
}
