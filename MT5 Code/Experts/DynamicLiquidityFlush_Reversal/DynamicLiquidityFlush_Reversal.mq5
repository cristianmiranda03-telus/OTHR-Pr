//+------------------------------------------------------------------+
//|                        DynamicLiquidityFlush_Reversal.mq5         |
//| DLFR - Session Anchored VWAP + DVB + Volume + Rejection - XAUUSD |
//+------------------------------------------------------------------+
#property copyright "Dynamic Liquidity Flush Reversal"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Session ==="
input int    InpNY_StartHour            = 13;         // 8 AM EST (server)
input int    InpNY_EndHour              = 21;         // 4 PM EST
input bool   InpResetVWAPDaily          = true;       // SA-VWAP from session start

input group "=== DVB (Dynamic Volatility Bands) ==="
input int    InpATR_Period              = 20;
input double InpDVB_Mult                = 2.0;        // Outer: SA-VWAP ± ATR*mult (1.5-3)
input double InpDVB_InnerMult           = 1.5;        // Inner band for absorption

input group "=== Volume Anomaly ==="
input int    InpVAF_Period              = 20;
input double InpVAF_Mult                = 1.5;        // Vol >= avg * this (1.5-2)

input group "=== Rejection Candle ==="
input double InpReject_CloseInBottomPct = 0.25;       // Close in bottom 25% (short)
input double InpReject_CloseInTopPct    = 0.25;       // Close in top 25% (long)

input group "=== Stop & Target ==="
input double InpSL_ATRBuffer            = 0.5;        // SL above rejection high + ATR buffer
input double InpTP1_RR                  = 1.75;       // TP1 at 1.5-2 R (partial close)
input double InpTP1_ClosePct            = 0.60;       // Close 50-70% at TP1
input double InpTrail_ATRMult           = 0.8;        // Trail 0.8*ATR behind swing
input double InpBE_ATRTrigger            = 1.0;        // Move to BE after 1 ATR profit

input group "=== Risk ==="
input double InpRiskPercent             = 0.5;
input double InpMaxLotSize              = 0.5;
input double InpMinLotSize              = 0.01;
input int    InpMagic                   = 405005;

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
datetime       g_sessionStart = 0;
double         g_vwapCumPV = 0, g_vwapCumV = 0;
int            g_atrHandle = INVALID_HANDLE;
ENUM_TIMEFRAMES InpTF = PERIOD_M1;

bool IsNewBar() { datetime t[]; ArraySetAsSeries(t, true); if (CopyTime(_Symbol, InpTF, 0, 1, t) < 1) return false; if (t[0] == g_lastBar) return false; g_lastBar = t[0]; return true; }
bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InNYSession() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); if (InpNY_EndHour > InpNY_StartHour) return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour); return (dt.hour >= InpNY_StartHour || dt.hour < InpNY_EndHour); }

void UpdateVWAP() {
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d %02d:00", dt.year, dt.mon, dt.day, InpNY_StartHour));
   if (now < todayStart) todayStart -= 24*3600;
   g_sessionStart = todayStart;
   int bars = (int)((now - g_sessionStart) / PeriodSeconds(InpTF)) + 5;
   if (bars > 500) bars = 500;
   if (bars < 1) return;
   double c[], v[]; ArraySetAsSeries(c, true); ArraySetAsSeries(v, true);
   if (CopyClose(_Symbol, InpTF, 0, bars, c) < bars) return;
   if (CopyTickVolume(_Symbol, InpTF, 0, bars, v) < bars) return;
   g_vwapCumPV = 0; g_vwapCumV = 0;
   for (int i = 0; i < bars; i++) { g_vwapCumPV += c[i] * (double)v[i]; g_vwapCumV += (double)v[i]; }
}

double GetSAVWAP() {
   UpdateVWAP();
   return (g_vwapCumV > 0) ? g_vwapCumPV / g_vwapCumV : 0;
}

double GetATR(int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(g_atrHandle, 0, shift, 1, b) < 1) return 0; return b[0]; }

bool VolumeAnomaly(int barIdx) {
   long v[]; ArraySetAsSeries(v, true);
   if (CopyRealVolume(_Symbol, InpTF, barIdx, InpVAF_Period + 1, v) < InpVAF_Period + 1) {
      if (CopyTickVolume(_Symbol, InpTF, barIdx, InpVAF_Period + 1, v) < InpVAF_Period + 1) return false;
   }
   double sum = 0; for (int i = 1; i <= InpVAF_Period; i++) sum += (double)v[i];
   double avg = sum / (double)InpVAF_Period;
   return (avg > 0 && (double)v[0] >= InpVAF_Mult * avg);
}

bool RejectionCandleShort(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] >= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double closePos = (c[0] - l[0]) / range;
   return (closePos <= InpReject_CloseInBottomPct);
}

bool RejectionCandleLong(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   if (c[0] <= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double closePos = (c[0] - l[0]) / range;
   return (closePos >= 1.0 - InpReject_CloseInTopPct);
}

bool PricePenetratedUpperDVB(int barIdx) {
   double h[]; ArraySetAsSeries(h, true);
   if (CopyHigh(_Symbol, InpTF, barIdx, 1, h) < 1) return false;
   double vwap = GetSAVWAP(); double atr = GetATR(barIdx);
   if (vwap <= 0 || atr <= 0) return false;
   return (h[0] >= vwap + atr * InpDVB_Mult);
}

bool PricePenetratedLowerDVB(int barIdx) {
   double l[]; ArraySetAsSeries(l, true);
   if (CopyLow(_Symbol, InpTF, barIdx, 1, l) < 1) return false;
   double vwap = GetSAVWAP(); double atr = GetATR(barIdx);
   if (vwap <= 0 || atr <= 0) return false;
   return (l[0] <= vwap - atr * InpDVB_Mult);
}

bool ConfirmationCandleShort(int barIdx) {
   double o[], c[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   double prevC[]; ArraySetAsSeries(prevC, true);
   if (CopyClose(_Symbol, InpTF, barIdx + 1, 1, prevC) < 1) return false;
   return (o[0] < prevC[0] && c[0] < o[0]);
}

bool ConfirmationCandleLong(int barIdx) {
   double o[], c[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTF, barIdx, 1, c) < 1) return false;
   double prevC[]; ArraySetAsSeries(prevC, true);
   if (CopyClose(_Symbol, InpTF, barIdx + 1, 1, prevC) < 1) return false;
   return (o[0] > prevC[0] && c[0] > o[0]);
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
   if (!IsXAU()) { Print("DLFR: XAU only."); return INIT_SUCCEEDED; }
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
   if (PositionCount() > 0) return;
   if (!IsNewBar()) return;

   double vwap = GetSAVWAP();
   if (vwap <= 0) return;
   double atr = GetATR(1);
   if (atr <= 0) return;
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (PricePenetratedUpperDVB(3) && VolumeAnomaly(2) && RejectionCandleShort(2)) {
      if (!ConfirmationCandleShort(1)) return;
      double rejH[]; ArraySetAsSeries(rejH, true);
      if (CopyHigh(_Symbol, InpTF, 2, 1, rejH) < 1) return;
      double sl = NormalizeDouble(rejH[0] + atr * InpSL_ATRBuffer, d);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double riskDist = sl - bid;
      if (riskDist <= 0) return;
      double tp1 = NormalizeDouble(bid - riskDist * InpTP1_RR, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Sell(lots, _Symbol, bid, sl, NormalizeDouble(vwap, d), "DLFR_S");
      return;
   }
   if (PricePenetratedLowerDVB(3) && VolumeAnomaly(2) && RejectionCandleLong(2)) {
      if (!ConfirmationCandleLong(1)) return;
      double rejL[]; ArraySetAsSeries(rejL, true);
      if (CopyLow(_Symbol, InpTF, 2, 1, rejL) < 1) return;
      double sl = NormalizeDouble(rejL[0] - atr * InpSL_ATRBuffer, d);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskDist = ask - sl;
      if (riskDist <= 0) return;
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Buy(lots, _Symbol, ask, sl, NormalizeDouble(vwap, d), "DLFR_L");
   }
}
