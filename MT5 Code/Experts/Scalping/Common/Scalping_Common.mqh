//+------------------------------------------------------------------+
//|                                          Scalping_Common.mqh     |
//| Shared utilities for all Scalping strategy EAs                   |
//| Assets: XAUUSD, BTCUSD, US500/SP500                              |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Session windows in UTC (broker time may differ, adjust InpUTCOffset)
//    Tokyo:           00:00 - 09:00 UTC
//    London:          07:00 - 16:00 UTC
//    New York:        13:00 - 22:00 UTC
//    London/NY Overlap: 13:00 - 16:00 UTC

//+------------------------------------------------------------------+
//| Session helpers                                                  |
//+------------------------------------------------------------------+
bool SC_IsInSession(int hourStart, int hourEnd, int utcOffsetHours)
{
   datetime now   = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now + utcOffsetHours * 3600, dt);
   int h = dt.hour;
   if (hourStart < hourEnd)
      return (h >= hourStart && h < hourEnd);
   else // overnight wrap
      return (h >= hourStart || h < hourEnd);
}

bool SC_IsTokyoSession(int utcOffset = 0)   { return SC_IsInSession(0,  9,  utcOffset); }
bool SC_IsLondonSession(int utcOffset = 0)  { return SC_IsInSession(7,  16, utcOffset); }
bool SC_IsNYSession(int utcOffset = 0)      { return SC_IsInSession(13, 22, utcOffset); }
bool SC_IsLondonNYOverlap(int utcOffset = 0){ return SC_IsInSession(13, 16, utcOffset); }
bool SC_IsAnyActiveSession(int utcOffset = 0)
{
   return SC_IsLondonSession(utcOffset) || SC_IsNYSession(utcOffset);
}

// Asian session in pure UTC (Tokyo ~00:00-09:00 UTC). Use for XAU night in Americas (UTC-6).
// If startHour > endHour, window wraps midnight (e.g. 22 -> 06 next day).
bool SC_IsAsianSessionUTC(int startHourUTC, int endHourUTC)
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if (startHourUTC < endHourUTC)
      return (h >= startHourUTC && h < endHourUTC);
   if (startHourUTC > endHourUTC)
      return (h >= startHourUTC || h < endHourUTC);
   return (h == startHourUTC);
}

//+------------------------------------------------------------------+
//| Price helpers (no-repaint: shift 1 = last closed bar)            |
//+------------------------------------------------------------------+
double SC_Close(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double a[]; ArraySetAsSeries(a, true);
   return (CopyClose(sym, tf, shift, 1, a) >= 1) ? a[0] : 0;
}
double SC_Open(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double a[]; ArraySetAsSeries(a, true);
   return (CopyOpen(sym, tf, shift, 1, a) >= 1) ? a[0] : 0;
}
double SC_High(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double a[]; ArraySetAsSeries(a, true);
   return (CopyHigh(sym, tf, shift, 1, a) >= 1) ? a[0] : 0;
}
double SC_Low(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   double a[]; ArraySetAsSeries(a, true);
   return (CopyLow(sym, tf, shift, 1, a) >= 1) ? a[0] : 0;
}

//+------------------------------------------------------------------+
//| Indicator helpers (release handle after use)                     |
//+------------------------------------------------------------------+
double SC_GetEMA(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

double SC_GetSMA(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iMA(sym, tf, period, 0, MODE_SMA, PRICE_CLOSE);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

double SC_GetATR(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iATR(sym, tf, period);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

double SC_GetRSI(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iRSI(sym, tf, period, PRICE_CLOSE);
   if (h == INVALID_HANDLE) return 50;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 50;
   IndicatorRelease(h);
   return v;
}

void SC_GetBB(const string sym, ENUM_TIMEFRAMES tf, int period, double deviation, int shift,
              double &upper, double &middle, double &lower)
{
   double u[], m[], l[];
   ArraySetAsSeries(u, true); ArraySetAsSeries(m, true); ArraySetAsSeries(l, true);
   int h = iBands(sym, tf, period, 0, deviation, PRICE_CLOSE);
   upper = middle = lower = 0;
   if (h == INVALID_HANDLE) return;
   if (CopyBuffer(h, 0, shift, 1, m) >= 1) middle = m[0];
   if (CopyBuffer(h, 1, shift, 1, u) >= 1) upper  = u[0];
   if (CopyBuffer(h, 2, shift, 1, l) >= 1) lower  = l[0];
   IndicatorRelease(h);
}

void SC_GetMACD(const string sym, ENUM_TIMEFRAMES tf,
                int fastPeriod, int slowPeriod, int signalPeriod, int shift,
                double &macdLine, double &signalLine)
{
   double m[], s[];
   ArraySetAsSeries(m, true); ArraySetAsSeries(s, true);
   int h = iMACD(sym, tf, fastPeriod, slowPeriod, signalPeriod, PRICE_CLOSE);
   macdLine = signalLine = 0;
   if (h == INVALID_HANDLE) return;
   if (CopyBuffer(h, 0, shift, 1, m) >= 1) macdLine   = m[0];
   if (CopyBuffer(h, 1, shift, 1, s) >= 1) signalLine = s[0];
   IndicatorRelease(h);
}

void SC_GetStoch(const string sym, ENUM_TIMEFRAMES tf,
                 int kPeriod, int dPeriod, int slowing, int shift,
                 double &k, double &d)
{
   double kb[], db[];
   ArraySetAsSeries(kb, true); ArraySetAsSeries(db, true);
   int h = iStochastic(sym, tf, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
   k = d = 50;
   if (h == INVALID_HANDLE) return;
   if (CopyBuffer(h, 0, shift, 1, kb) >= 1) k = kb[0];
   if (CopyBuffer(h, 1, shift, 1, db) >= 1) d = db[0];
   IndicatorRelease(h);
}

double SC_GetCCI(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iCCI(sym, tf, period, PRICE_TYPICAL);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

// Returns highest high over 'period' bars starting at 'shift'
double SC_GetHighestHigh(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double hi[];
   ArraySetAsSeries(hi, true);
   if (CopyHigh(sym, tf, shift, period, hi) < period) return 0;
   double mx = hi[0];
   for (int i = 1; i < period; i++) if (hi[i] > mx) mx = hi[i];
   return mx;
}

double SC_GetLowestLow(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double lo[];
   ArraySetAsSeries(lo, true);
   if (CopyLow(sym, tf, shift, period, lo) < period) return 0;
   double mn = lo[0];
   for (int i = 1; i < period; i++) if (lo[i] < mn) mn = lo[i];
   return mn;
}

// Average of Real Volume over N bars
double SC_AvgVolume(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   long vols[];
   ArraySetAsSeries(vols, true);
   int got = (int)CopyRealVolume(sym, tf, shift, period, vols);
   if (got < 1) return 0;
   double sum = 0;
   for (int i = 0; i < got; i++) sum += (double)vols[i];
   return sum / got;
}

long SC_Volume(const string sym, ENUM_TIMEFRAMES tf, int shift)
{
   long v[]; ArraySetAsSeries(v, true);
   return (CopyRealVolume(sym, tf, shift, 1, v) >= 1) ? v[0] : 0;
}

// Parabolic SAR
double SC_GetSAR(const string sym, ENUM_TIMEFRAMES tf, double step, double max, int shift = 1)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iSAR(sym, tf, step, max);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

//+------------------------------------------------------------------+
//| Lot sizing by risk %                                             |
//+------------------------------------------------------------------+
double SC_CalcLotSize(double slPoints, double riskPct, double minLot, double maxLot)
{
   if (slPoints <= 0) return minLot;
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = equity * (riskPct / 100.0);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (tickVal <= 0 || tickSize <= 0 || point <= 0) return minLot;
   double valPerPtPerLot = tickVal * (point / tickSize);
   if (valPerPtPerLot <= 0) return minLot;
   double lots  = riskAmt / (slPoints * valPerPtPerLot);
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(maxL, lots));
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
//| Position helpers                                                 |
//+------------------------------------------------------------------+
int SC_CountPositions(ENUM_POSITION_TYPE type, ulong magic)
{
   int n = 0;
   CPositionInfo pos;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!pos.SelectByIndex(i)) continue;
      if (pos.Symbol() != _Symbol || pos.Magic() != magic) continue;
      if (pos.PositionType() == type) n++;
   }
   return n;
}

int SC_TotalPositions(ulong magic)
{
   return SC_CountPositions(POSITION_TYPE_BUY,  magic) +
          SC_CountPositions(POSITION_TYPE_SELL, magic);
}

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool SC_IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastTime)
{
   datetime t[];
   ArraySetAsSeries(t, true);
   if (CopyTime(_Symbol, tf, 0, 1, t) < 1) return false;
   if (t[0] != lastTime) { lastTime = t[0]; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool SC_SpreadOK(int maxSpreadPts)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) point = _Point;
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point;
   return (spread <= maxSpreadPts);
}

//+------------------------------------------------------------------+
//| Fill mode auto-detect                                            |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING SC_GetFillMode()
{
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if ((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
