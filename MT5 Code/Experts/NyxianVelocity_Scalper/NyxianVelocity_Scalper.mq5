//+------------------------------------------------------------------+
//|                                  NyxianVelocity_Scalper.mq5      |
//| Nyxian Velocity - SMC + Velocity Vortex + Rejection Shadow      |
//| XAUUSD M1, NY 8-11 AM EST                                        |
//+------------------------------------------------------------------+
#property copyright "Nyxian Velocity Scalper"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Session ==="
input int    InpNY_StartHour            = 13;         // 8 AM EST (server)
input int    InpNY_EndHour               = 16;         // 11 AM EST (server)

input group "=== Velocity Vortex (GVO + IIO) ==="
input int    InpGVO_Bars                = 5;          // GVO = sum tick vol last N
input int    InpGVO_SMA                  = 20;
input double InpGVO_StdDevMult           = 2.0;        // GMVS: GVO >= SMA + this*SD
input int    InpIIO_Period               = 3;          // RSI period (IIO)
input double InpIIO_LongExtreme          = 10;         // Oversold then reverse
input double InpIIO_LongCross            = 20;
input double InpIIO_ShortExtreme        = 90;
input double InpIIO_ShortCross           = 80;

input group "=== Rejection Shadow ==="
input double InpReject_WickPct           = 0.50;       // Wick >= 50% range
input double InpReject_BodyClosePct      = 0.50;       // Body close 50% above wick low

input group "=== SMC Zone (simplified) ==="
input int    InpSwingBars                = 20;        // Swing high/low lookback
input double InpZonePoints               = 100;       // Points tolerance for zone touch

input group "=== Stop & Target ==="
input int    InpATR_Period              = 14;
input int    InpATR_TrailPeriod         = 5;
input double InpSL_ATRMult              = 1.5;
input double InpSL_MinBeyondWick        = 0.05;       // Min 5 cents beyond wick
input double InpBE_TriggerR             = 1.0;
input double InpTrail_ATRMult          = 1.0;
input double InpTP_PartialRR            = 1.0;        // Close 50% at 1R
input double InpTP_MaxRR                 = 2.5;

input group "=== Risk ==="
input double InpRiskPercent             = 0.5;
input double InpMaxLotSize              = 0.5;
input double InpMinLotSize              = 0.01;
input int    InpMagic                   = 403003;

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_atrHandle = INVALID_HANDLE;
int            g_atr5Handle = INVALID_HANDLE;
int            g_rsiHandle = INVALID_HANDLE;

bool IsNewBar() { datetime t[]; ArraySetAsSeries(t, true); if (CopyTime(_Symbol, PERIOD_M1, 0, 1, t) < 1) return false; if (t[0] == g_lastBar) return false; g_lastBar = t[0]; return true; }
bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InNYSession() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour); }

double GetATR(int h, int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(h, 0, shift, 1, b) < 1) return 0; return b[0]; }
double GetRSI(int shift) { double b[]; ArraySetAsSeries(b, true); if (CopyBuffer(g_rsiHandle, 0, shift, 1, b) < 1) return 0; return b[0]; }

bool GMVS_Detected() {
   long v[]; ArraySetAsSeries(v, true);
   if (CopyTickVolume(_Symbol, PERIOD_M1, 1, InpGVO_Bars + InpGVO_SMA, v) < InpGVO_Bars + InpGVO_SMA) return false;
   double gvo = 0; for (int i = 0; i < InpGVO_Bars; i++) gvo += (double)v[i];
   double sum = 0; for (int i = 0; i < InpGVO_SMA; i++) { double g = 0; for (int j = 0; j < InpGVO_Bars; j++) g += (double)v[i+j]; sum += g; }
   double sma = sum / (double)InpGVO_SMA;
   double var = 0; for (int i = 0; i < InpGVO_SMA; i++) { double g = 0; for (int j = 0; j < InpGVO_Bars; j++) g += (double)v[i+j]; var += (g - sma)*(g - sma); }
   double sd = MathSqrt(var / (double)InpGVO_SMA);
   return (sd > 0 && gvo >= sma + InpGVO_StdDevMult * sd);
}

bool IIO_LongReversal() {
   double r[]; ArraySetAsSeries(r, true);
   if (CopyBuffer(g_rsiHandle, 0, 1, 5, r) < 5) return false;
   bool hadExtreme = false;
   for (int i = 1; i < 5; i++) if (r[i] < InpIIO_LongExtreme) { hadExtreme = true; break; }
   return (hadExtreme && r[0] > InpIIO_LongCross && r[1] <= InpIIO_LongCross);
}

bool IIO_ShortReversal() {
   double r[]; ArraySetAsSeries(r, true);
   if (CopyBuffer(g_rsiHandle, 0, 1, 5, r) < 5) return false;
   bool hadExtreme = false;
   for (int i = 1; i < 5; i++) if (r[i] > InpIIO_ShortExtreme) { hadExtreme = true; break; }
   return (hadExtreme && r[0] < InpIIO_ShortCross && r[1] >= InpIIO_ShortCross);
}

double RecentSwingLow(int bars) {
   double l[]; ArraySetAsSeries(l, true);
   if (CopyLow(_Symbol, PERIOD_M1, 1, bars, l) < bars) return 0;
   double minL = l[0]; for (int i = 1; i < bars; i++) if (l[i] < minL) minL = l[i]; return minL;
}
double RecentSwingHigh(int bars) {
   double h[]; ArraySetAsSeries(h, true);
   if (CopyHigh(_Symbol, PERIOD_M1, 1, bars, h) < bars) return 0;
   double maxH = h[0]; for (int i = 1; i < bars; i++) if (h[i] > maxH) maxH = h[i]; return maxH;
}

bool PriceInBullishZone() {
   double swingL = RecentSwingLow(InpSwingBars);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * InpZonePoints;
   return (swingL > 0 && bid >= swingL - pt && bid <= swingL + pt);
}
bool PriceInBearishZone() {
   double swingH = RecentSwingHigh(InpSwingBars);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * InpZonePoints;
   return (swingH > 0 && ask <= swingH + pt && ask >= swingH - pt);
}

bool RejectionShadowLong(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M1, barIdx, 1, o) < 1 || CopyClose(_Symbol, PERIOD_M1, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M1, barIdx, 1, h) < 1 || CopyLow(_Symbol, PERIOD_M1, barIdx, 1, l) < 1) return false;
   if (c[0] <= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double lowerWick = MathMin(o[0], c[0]) - l[0];
   if (lowerWick < range * InpReject_WickPct) return false;
   if ((c[0] - l[0]) < range * InpReject_BodyClosePct) return false;
   return true;
}

bool RejectionShadowShort(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M1, barIdx, 1, o) < 1 || CopyClose(_Symbol, PERIOD_M1, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M1, barIdx, 1, h) < 1 || CopyLow(_Symbol, PERIOD_M1, barIdx, 1, l) < 1) return false;
   if (c[0] >= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double upperWick = h[0] - MathMax(o[0], c[0]);
   if (upperWick < range * InpReject_WickPct) return false;
   if ((h[0] - c[0]) < range * InpReject_BodyClosePct) return false;
   return true;
}

bool NextCandleClosesAboveWickLow(int rejectBar) {
   double l[]; ArraySetAsSeries(l, true);
   if (CopyLow(_Symbol, PERIOD_M1, rejectBar, 1, l) < 1) return false;
   double c[]; ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, PERIOD_M1, rejectBar - 1, 1, c) < 1) return false;
   return (c[0] > l[0]);
}
bool NextCandleClosesBelowWickHigh(int rejectBar) {
   double h[]; ArraySetAsSeries(h, true);
   if (CopyHigh(_Symbol, PERIOD_M1, rejectBar, 1, h) < 1) return false;
   double c[]; ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, PERIOD_M1, rejectBar - 1, 1, c) < 1) return false;
   return (c[0] < h[0]);
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
   if (!IsXAU()) { Print("Nyxian Velocity: XAU only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_atrHandle = iATR(_Symbol, PERIOD_M1, InpATR_Period);
   g_atr5Handle = iATR(_Symbol, PERIOD_M1, InpATR_TrailPeriod);
   g_rsiHandle = iRSI(_Symbol, PERIOD_M1, InpIIO_Period, PRICE_CLOSE);
   if (g_atrHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE) return INIT_FAILED;
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
   if (g_atr5Handle != INVALID_HANDLE) IndicatorRelease(g_atr5Handle);
   if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
}

void OnTick() {
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!InNYSession()) return;
   if (PositionCount() > 0) return;

   if (!IsNewBar()) return;
   if (!GMVS_Detected()) return;

   double atr14 = GetATR(g_atrHandle, 1); double atr5 = GetATR(g_atr5Handle, 1);
   if (atr14 <= 0) return;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (PriceInBullishZone() && IIO_LongReversal() && RejectionShadowLong(1) && NextCandleClosesAboveWickLow(1)) {
      double rejL[]; ArraySetAsSeries(rejL, true);
      if (CopyLow(_Symbol, PERIOD_M1, 1, 1, rejL) < 1) return;
      double slDist = MathMax(atr14 * InpSL_ATRMult, InpSL_MinBeyondWick);
      double sl = NormalizeDouble(rejL[0] - slDist, d);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if (sl >= ask) return;
      double riskDist = ask - sl;
      double tp = NormalizeDouble(ask + riskDist * InpTP_MaxRR, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Buy(lots, _Symbol, ask, sl, tp, "Nyx_L");
      return;
   }
   if (PriceInBearishZone() && IIO_ShortReversal() && RejectionShadowShort(1) && NextCandleClosesBelowWickHigh(1)) {
      double rejH[]; ArraySetAsSeries(rejH, true);
      if (CopyHigh(_Symbol, PERIOD_M1, 1, 1, rejH) < 1) return;
      double slDist = MathMax(atr14 * InpSL_ATRMult, InpSL_MinBeyondWick);
      double sl = NormalizeDouble(rejH[0] + slDist, d);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if (sl <= bid) return;
      double riskDist = sl - bid;
      double tp = NormalizeDouble(bid - riskDist * InpTP_MaxRR, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) g_trade.Sell(lots, _Symbol, bid, sl, tp, "Nyx_S");
   }
}
