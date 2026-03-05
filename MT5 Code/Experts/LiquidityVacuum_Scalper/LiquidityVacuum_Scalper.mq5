//+------------------------------------------------------------------+
//|                              LiquidityVacuum_Scalper.mq5         |
//| Pulse & Discontinuity - XAUUSD 1-2 min, NY Session               |
//+------------------------------------------------------------------+
#property copyright "Liquidity Vacuum Scalper"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Timeframe & Session ==="
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_M1;  // Chart timeframe (M1 or M2)
input int    InpNY_StartHour             = 14;         // NY start hour (server time, e.g. 14=9:30 EST)
input int    InpNY_EndHour               = 21;         // NY end hour (server time, e.g. 21=4:00 PM EST)
input int    InpNewsPauseMins            = 15;         // No trade N mins around news (0=disabled)

input group "=== Pulse Candle ==="
input double InpPulse_RangeATRMult       = 1.5;        // Range >= ATR5 * this
input double InpPulse_VolMult            = 2.5;        // Volume > SMA(vol,20) * this
input double InpPulse_BodyPct            = 0.75;       // Body > 75% of range
input double InpPulse_MaxWickPct         = 0.25;       // Opposing wick < 25% of range

input group "=== Discontinuity Candle ==="
input double InpDisc_VolRatio            = 0.5;        // Vol < Pulse vol * this
input double InpDisc_RangePct            = 0.40;       // Range < Pulse range * this
input double InpDisc_BodyOwnRangePct     = 0.20;       // Body < 20% own range
input double InpDisc_BodyVsPulsePct      = 0.30;       // Body < 30% Pulse body

input group "=== Volatility Filter ==="
input int    InpATR_Period               = 5;          // ATR period
input int    InpATR_EMAPeriod            = 60;         // EMA of ATR (60 for M1, 30 for M2)

input group "=== Stop & Target ==="
input double InpSL_ATRBuffer             = 0.8;        // SL buffer beyond Pulse (ATR mult)
input double InpTP_RR_Min                 = 1.8;        // TP min R:R
input double InpTP_RR_Max                 = 2.2;        // TP max R:R
input double InpTrail_ActivateR          = 1.0;        // Trail activates at profit (R)
input double InpTrail_ATRMult             = 1.8;        // Trail distance (ATR mult)
input double InpBE_ATRBuffer             = 0.5;        // Breakeven buffer (ATR)

input group "=== Counter-Pulse Exit ==="
input double InpCounter_VolSMA           = 2.0;        // Vol > SMA(20)*this
input double InpCounter_VolVsPulse        = 1.0;        // Vol > original Pulse vol * this
input double InpCounter_BodyPct          = 0.65;       // Body > 65% range, opposite dir

input group "=== Time Exit ==="
input int    InpTimeExitBars             = 10;         // Exit after N bars (10 for M1, 6 for M2)

input group "=== Risk ==="
input double InpRiskPercent              = 0.5;
input double InpMaxLotSize               = 0.5;
input double InpMinLotSize               = 0.01;
input int    InpMagic                    = 401001;

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_atrHandle = INVALID_HANDLE;

struct TradeContext { double pulseHigh; double pulseLow; double pulseVol; double pulseRange; int direction; datetime entryTime; double entryPrice; double initialSL; bool trailActive; };
TradeContext g_ctx = {0,0,0,0,0,0,0,0,false};

bool IsNewBar() {
   datetime t[]; ArraySetAsSeries(t, true);
   if (CopyTime(_Symbol, InpTimeframe, 0, 1, t) < 1) return false;
   if (t[0] == g_lastBar) { return false; } g_lastBar = t[0]; return true;
}
bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InNYSession() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if (InpNY_EndHour > InpNY_StartHour) return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour);
   return (dt.hour >= InpNY_StartHour || dt.hour < InpNY_EndHour);
}

double GetATR(int shift) {
   double b[]; ArraySetAsSeries(b, true);
   if (CopyBuffer(g_atrHandle, 0, shift, 1, b) < 1) return 0; return b[0];
}
double GetATRBaseline(int shift) {
   double b[]; ArraySetAsSeries(b, true);
   if (CopyBuffer(g_atrHandle, 0, shift, InpATR_EMAPeriod, b) < InpATR_EMAPeriod) return 0;
   double sum = 0; for (int i = 0; i < InpATR_EMAPeriod; i++) sum += b[i];
   return sum / (double)InpATR_EMAPeriod;
}

double SMA_Volume(int period, int startShift) {
   long v[]; ArraySetAsSeries(v, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, startShift, period, v) < period) return 0;
   double s = 0; for (int i = 0; i < period; i++) s += (double)v[i]; return s / (double)period;
}

bool VolatilityFilterOK() {
   double atr = GetATR(1), baseline = GetATRBaseline(1);
   return (atr > 0 && baseline > 0 && atr > baseline);
}

bool IsPulseBullish(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTimeframe, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTimeframe, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTimeframe, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTimeframe, barIdx, 1, l) < 1) return false;
   if (c[0] <= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double body = c[0] - o[0];
   double lowerWick = MathMin(o[0], c[0]) - l[0];
   double atr5 = GetATR(barIdx + 1);
   if (atr5 <= 0) return false;
   if (range < InpPulse_RangeATRMult * atr5) return false;
   long vol[]; ArraySetAsSeries(vol, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, barIdx, 1, vol) < 1) return false;
   double avgVol = SMA_Volume(20, barIdx + 1);
   if (avgVol <= 0 || (double)vol[0] <= InpPulse_VolMult * avgVol) return false;
   if (body / range < InpPulse_BodyPct) return false;
   if (lowerWick / range > InpPulse_MaxWickPct) return false;
   return true;
}

bool IsPulseBearish(int barIdx) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTimeframe, barIdx, 1, o) < 1 || CopyClose(_Symbol, InpTimeframe, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTimeframe, barIdx, 1, h) < 1 || CopyLow(_Symbol, InpTimeframe, barIdx, 1, l) < 1) return false;
   if (c[0] >= o[0]) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double body = o[0] - c[0];
   double upperWick = h[0] - MathMax(o[0], c[0]);
   double atr5 = GetATR(barIdx + 1);
   if (atr5 <= 0) return false;
   if (range < InpPulse_RangeATRMult * atr5) return false;
   long vol[]; ArraySetAsSeries(vol, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, barIdx, 1, vol) < 1) return false;
   double avgVol = SMA_Volume(20, barIdx + 1);
   if (avgVol <= 0 || (double)vol[0] <= InpPulse_VolMult * avgVol) return false;
   if (body / range < InpPulse_BodyPct) return false;
   if (upperWick / range > InpPulse_MaxWickPct) return false;
   return true;
}

bool IsDiscontinuityAfterPulse(int discBarIdx, double pulseVol, double pulseRange, double pulseBody) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTimeframe, discBarIdx, 1, o) < 1 || CopyClose(_Symbol, InpTimeframe, discBarIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTimeframe, discBarIdx, 1, h) < 1 || CopyLow(_Symbol, InpTimeframe, discBarIdx, 1, l) < 1) return false;
   long vol[]; ArraySetAsSeries(vol, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, discBarIdx, 1, vol) < 1) return false;
   if ((double)vol[0] >= InpDisc_VolRatio * pulseVol) return false;
   double range = h[0] - l[0]; if (range >= InpDisc_RangePct * pulseRange) return false;
   double body = MathAbs(c[0] - o[0]);
   if (range > 1e-9 && body / range >= InpDisc_BodyOwnRangePct) return false;
   if (pulseBody > 1e-9 && body >= InpDisc_BodyVsPulsePct * pulseBody) return false;
   return true;
}

bool CounterPulseDetected(int dir, double pulseVol) {
   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTimeframe, 1, 1, o) < 1 || CopyClose(_Symbol, InpTimeframe, 1, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, InpTimeframe, 1, 1, h) < 1 || CopyLow(_Symbol, InpTimeframe, 1, 1, l) < 1) return false;
   long vol[]; ArraySetAsSeries(vol, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, 1, 1, vol) < 1) return false;
   double avgVol = SMA_Volume(20, 2);
   if (avgVol <= 0 || (double)vol[0] < InpCounter_VolSMA * avgVol || (double)vol[0] < InpCounter_VolVsPulse * pulseVol) return false;
   double range = h[0] - l[0]; if (range < 1e-9) return false;
   double body = MathAbs(c[0] - o[0]);
   if (body / range < InpCounter_BodyPct) return false;
   if (dir == 1 && c[0] < o[0]) return true;  // we're long, bearish counter-pulse
   if (dir == -1 && c[0] > o[0]) return true; // we're short, bullish counter-pulse
   return false;
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

int PositionType() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!g_position.SelectByIndex(i)) continue;
      if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
      return g_position.PositionType() == POSITION_TYPE_BUY ? 1 : -1;
   }
   return 0;
}

bool ModifySLTP(ulong ticket, double sl, double tp) {
   return g_trade.PositionModify(ticket, sl, tp);
}

int OnInit() {
   if (!IsXAU()) { Print("Liquidity Vacuum: XAU only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_atrHandle = iATR(_Symbol, InpTimeframe, InpATR_Period);
   if (g_atrHandle == INVALID_HANDLE) return INIT_FAILED;
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
}

void OnTick() {
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!InNYSession()) return;

   int posDir = PositionType();
   if (posDir != 0) {
      for (int i = PositionsTotal() - 1; i >= 0; i--) {
         if (!g_position.SelectByIndex(i)) continue;
         if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
         ulong ticket = g_position.Ticket();
         double posOpen = g_position.PriceOpen();
         double posSL = g_position.StopLoss();
         double posTP = g_position.TakeProfit();
         if (CounterPulseDetected(posDir, g_ctx.pulseVol)) { g_trade.PositionClose(ticket); continue; }
         int barsOpen = (int)((TimeCurrent() - g_ctx.entryTime) / PeriodSeconds(InpTimeframe));
         if (barsOpen >= InpTimeExitBars) { g_trade.PositionClose(ticket); continue; }
         double atr5 = GetATR(1);
         if (posDir == 1) {
            double riskDist = posOpen - g_ctx.initialSL;
            if (!g_ctx.trailActive && SymbolInfoDouble(_Symbol, SYMBOL_BID) >= posOpen + riskDist) {
               g_ctx.trailActive = true;
               double be = NormalizeDouble(posOpen + atr5 * InpBE_ATRBuffer, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
               ModifySLTP(ticket, be, posTP);
            } else if (g_ctx.trailActive && atr5 > 0) {
               double hh[]; ArraySetAsSeries(hh, true);
               if (CopyHigh(_Symbol, InpTimeframe, 1, 30, hh) >= 30) {
                  double maxH = hh[0]; for (int k = 1; k < 30; k++) if (hh[k] > maxH) maxH = hh[k];
                  double newSL = NormalizeDouble(maxH - atr5 * InpTrail_ATRMult, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                  if (newSL > posSL && newSL < SymbolInfoDouble(_Symbol, SYMBOL_BID))
                     ModifySLTP(ticket, newSL, posTP);
               }
            }
         } else {
            double riskDist = g_ctx.initialSL - posOpen;
            if (!g_ctx.trailActive && SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= posOpen - riskDist) {
               g_ctx.trailActive = true;
               double be = NormalizeDouble(posOpen - atr5 * InpBE_ATRBuffer, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
               ModifySLTP(ticket, be, posTP);
            } else if (g_ctx.trailActive && atr5 > 0) {
               double ll[]; ArraySetAsSeries(ll, true);
               if (CopyLow(_Symbol, InpTimeframe, 1, 30, ll) >= 30) {
                  double minL = ll[0]; for (int k = 1; k < 30; k++) if (ll[k] < minL) minL = ll[k];
                  double newSL = NormalizeDouble(minL + atr5 * InpTrail_ATRMult, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                  if (newSL > SymbolInfoDouble(_Symbol, SYMBOL_ASK) && (posSL == 0 || newSL < posSL)) ModifySLTP(ticket, newSL, posTP);
               }
            }
         }
      }
      return;
   }

   if (!IsNewBar()) return;
   if (!VolatilityFilterOK()) return;

   double o[], c[], h[], l[]; ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, InpTimeframe, 2, 2, o) < 2 || CopyClose(_Symbol, InpTimeframe, 2, 2, c) < 2) return;
   if (CopyHigh(_Symbol, InpTimeframe, 2, 2, h) < 2 || CopyLow(_Symbol, InpTimeframe, 2, 2, l) < 2) return;
   long vol[]; ArraySetAsSeries(vol, true);
   if (CopyRealVolume(_Symbol, InpTimeframe, 2, 2, vol) < 2) return;

   double pulseRange = h[1] - l[1], pulseBody = MathAbs(c[1] - o[1]);
   double pulseVol = (double)vol[1];

   if (IsPulseBullish(2) && IsDiscontinuityAfterPulse(1, pulseVol, pulseRange, pulseBody)) {
      double atr5 = GetATR(1); if (atr5 <= 0) return;
      int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl = NormalizeDouble(l[1] - atr5 * InpSL_ATRBuffer, d);
      double rr = (InpTP_RR_Min + InpTP_RR_Max) / 2.0;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskDist = ask - sl;
      double tp = NormalizeDouble(ask + riskDist * rr, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) {
         if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "LV_L")) {
            g_ctx.pulseHigh = h[1]; g_ctx.pulseLow = l[1]; g_ctx.pulseVol = pulseVol; g_ctx.pulseRange = pulseRange; g_ctx.direction = 1;
            g_ctx.entryTime = TimeCurrent(); g_ctx.entryPrice = ask; g_ctx.initialSL = sl; g_ctx.trailActive = false;
         }
      }
      return;
   }
   if (IsPulseBearish(2) && IsDiscontinuityAfterPulse(1, pulseVol, pulseRange, pulseBody)) {
      double atr5 = GetATR(1); if (atr5 <= 0) return;
      int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl = NormalizeDouble(h[1] + atr5 * InpSL_ATRBuffer, d);
      double rr = (InpTP_RR_Min + InpTP_RR_Max) / 2.0;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double riskDist = sl - bid;
      double tp = NormalizeDouble(bid - riskDist * rr, d);
      double lots = CalcLots(riskDist, InpRiskPercent);
      if (lots >= InpMinLotSize) {
         if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "LV_S")) {
            g_ctx.pulseHigh = h[1]; g_ctx.pulseLow = l[1]; g_ctx.pulseVol = pulseVol; g_ctx.pulseRange = pulseRange; g_ctx.direction = -1;
            g_ctx.entryTime = TimeCurrent(); g_ctx.entryPrice = bid; g_ctx.initialSL = sl; g_ctx.trailActive = false;
         }
      }
   }
}
