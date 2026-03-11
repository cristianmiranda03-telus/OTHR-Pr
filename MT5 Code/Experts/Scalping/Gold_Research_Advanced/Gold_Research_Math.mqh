//+------------------------------------------------------------------+
//| Gold_Research_Math.mqh                                           |
//| Advanced math library for Gold_Research_Advanced EAs            |
//| Implements: Kalman Filter, Hurst Exponent (R/S), LSF Slope,     |
//| Volume Delta, Hidden Divergence, ADX helper, ATR Ratio          |
//|                                                                  |
//| Scientific basis:                                                |
//| - Kalman+DRL: thesai.org/Downloads/Volume16No11/Paper_81        |
//| - Hurst/Gold: IDEAS RePEc 2024 (Hurst-reconfiguration ML)       |
//| - LSF: LSF-X Engine MT5 (dhruuvsharma/LSF-X-Engine)             |
//| - Pullback: ilahuerta-IA/backtrader-pullback-window-xauusd      |
//+------------------------------------------------------------------+
#ifndef GOLD_RESEARCH_MATH_MQH
#define GOLD_RESEARCH_MATH_MQH

//+------------------------------------------------------------------+
//| KALMAN FILTER - 1D scalar with velocity (momentum) tracking     |
//| Based on Kalman-enhanced DRL framework (2025 paper)             |
//| Q = process noise (sensitivity), R = measurement noise (smooth) |
//| Lower R = trust measurement more; higher R = trust model more   |
//+------------------------------------------------------------------+
double GRM_KalmanUpdate(double z, double &x_est, double &p_est,
                        double Q = 1e-4, double R = 0.01)
{
   double x_pred = x_est;
   double p_pred = p_est + Q;
   double K      = p_pred / (p_pred + R);
   x_est = x_pred + K * (z - x_pred);
   p_est = (1.0 - K) * p_pred;
   return x_est;
}

// Initialize Kalman state with first price observation
void GRM_KalmanInit(double z, double &x_est, double &p_est,
                    double initUncertainty = 1.0)
{
   x_est = z;
   p_est = initUncertainty;
}

// Run Kalman over array of prices, store filtered values; returns velocity (last slope)
double GRM_KalmanBatch(const string sym, ENUM_TIMEFRAMES tf, int bars, int shift,
                       double &filtered[], double Q = 1e-4, double R = 0.01)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   int needed = bars + shift;
   if (CopyClose(sym, tf, 0, needed, closes) < needed) return 0;

   ArrayResize(filtered, bars);
   // Warm up on oldest data
   double x = closes[needed - 1];
   double p = 1.0;
   for (int i = needed - 1; i >= shift; i--)
      x = GRM_KalmanUpdate(closes[i], x, p, Q, R);

   // Fill filtered array (index 0 = most recent bar relative to shift)
   double xs = x, ps = p;
   // Re-run for clean indexed output
   xs = closes[shift + bars - 1];
   ps = 1.0;
   for (int i = bars - 1; i >= 0; i--)
   {
      filtered[i] = GRM_KalmanUpdate(closes[shift + i], xs, ps, Q, R);
   }
   // Velocity = change over last 2 filtered values
   if (bars >= 2) return filtered[0] - filtered[1];
   return 0;
}

//+------------------------------------------------------------------+
//| LSF SLOPE (Least Squares Fit linear regression slope)           |
//| Based on LSF-X Engine trend detection                           |
//| Positive = uptrend; negative = downtrend; near 0 = consolidation|
//+------------------------------------------------------------------+
double GRM_LSFSlope(double &values[], int n)
{
   if (n < 3) return 0;
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for (int i = 0; i < n; i++)
   {
      sx  += i;
      sy  += values[i];
      sxy += i * values[i];
      sxx += i * i;
   }
   double denom = (double)n * sxx - sx * sx;
   if (denom == 0) return 0;
   return ((double)n * sxy - sx * sy) / denom;
}

// Normalized LSF slope relative to ATR (so it's comparable across instruments)
double GRM_LSFSlopeNorm(double &values[], int n, double atr)
{
   if (atr <= 0) return 0;
   return GRM_LSFSlope(values, n) / atr;
}

//+------------------------------------------------------------------+
//| HURST EXPONENT via Rescaled Range (R/S) Analysis                |
//| Based on: Comparison of Fractal Dimension Algorithms by Hurst   |
//| H > 0.55 = persistent/trending; H < 0.45 = anti-persistent/MR  |
//| H ~ 0.5  = random walk (no edge)                                |
//+------------------------------------------------------------------+
double GRM_HurstRS(const string sym, ENUM_TIMEFRAMES tf, int n, int shift = 1)
{
   if (n < 32) return 0.5;
   double closes[];
   ArraySetAsSeries(closes, true);
   if (CopyClose(sym, tf, shift, n + 1, closes) < n + 1) return 0.5;

   // Build log returns
   double ret[];
   ArrayResize(ret, n);
   for (int i = 0; i < n; i++)
   {
      if (closes[i + 1] <= 0) { ret[i] = 0; continue; }
      ret[i] = MathLog(closes[i] / closes[i + 1]);
   }

   // Compute R/S at multiple lags for linear regression
   int lags[] = {8, 16, 32, 48};
   int nlags   = ArraySize(lags);
   double logRS[], logN[];
   ArrayResize(logRS, nlags);
   ArrayResize(logN,  nlags);
   int count = 0;

   for (int li = 0; li < nlags; li++)
   {
      int L = lags[li];
      if (L >= n) continue;

      // Mean
      double mu = 0;
      for (int i = 0; i < L; i++) mu += ret[i];
      mu /= L;

      // Cumulative deviation, range
      double cumDev = 0, maxCD = 0, minCD = 0;
      for (int i = 0; i < L; i++)
      {
         cumDev += ret[i] - mu;
         if (cumDev > maxCD) maxCD = cumDev;
         if (cumDev < minCD) minCD = cumDev;
      }
      double R = maxCD - minCD;

      // Standard deviation
      double variance = 0;
      for (int i = 0; i < L; i++) variance += (ret[i] - mu) * (ret[i] - mu);
      double stdDev = MathSqrt(variance / L);

      if (stdDev <= 0 || R <= 0) continue;

      logRS[count] = MathLog(R / stdDev);
      logN[count]  = MathLog((double)L);
      count++;
   }

   if (count < 2) return 0.5;

   // Linear regression slope on log-log = Hurst exponent
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for (int i = 0; i < count; i++)
   {
      sx  += logN[i];
      sy  += logRS[i];
      sxy += logN[i] * logRS[i];
      sxx += logN[i] * logN[i];
   }
   double denom = (double)count * sxx - sx * sx;
   if (denom == 0) return 0.5;
   double H = ((double)count * sxy - sx * sy) / denom;
   return MathMax(0.1, MathMin(0.9, H));
}

//+------------------------------------------------------------------+
//| VOLUME DELTA (directional volume pressure per bar)              |
//| Based on order flow imbalance research (fxpremiere 2025)        |
//| Returns: positive = buying pressure, negative = selling pressure |
//+------------------------------------------------------------------+
double GRM_BarVolumeDelta(double open, double close, long volume)
{
   if (close > open) return  (double)volume;
   if (close < open) return -(double)volume;
   return 0;
}

// Cumulative delta over last N bars (shift=1 avoids current bar)
double GRM_CumDelta(const string sym, ENUM_TIMEFRAMES tf, int bars, int shift = 1)
{
   double o[], c[];
   long   v[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(v, true);
   int needed = bars + shift;
   if (CopyOpen(sym, tf, 0, needed, o)  < needed) return 0;
   if (CopyClose(sym, tf, 0, needed, c) < needed) return 0;
   int vgot = (int)CopyRealVolume(sym, tf, 0, needed, v);
   if (vgot < needed) vgot = (int)CopyTickVolume(sym, tf, 0, needed, v);
   if (vgot < needed) return 0;

   double cumDelta = 0;
   for (int i = shift; i < shift + bars; i++)
      cumDelta += GRM_BarVolumeDelta(o[i], c[i], v[i]);
   return cumDelta;
}

// Count of consecutive bars with same delta direction (shift=1)
// Returns positive count for bullish streak, negative for bearish
int GRM_DeltaStreak(const string sym, ENUM_TIMEFRAMES tf, int maxLook, int shift = 1)
{
   double o[], c[];
   long   v[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(v, true);
   int needed = maxLook + shift;
   if (CopyOpen(sym, tf, 0, needed, o)  < needed) return 0;
   if (CopyClose(sym, tf, 0, needed, c) < needed) return 0;
   int vgot = (int)CopyRealVolume(sym, tf, 0, needed, v);
   if (vgot < needed) vgot = (int)CopyTickVolume(sym, tf, 0, needed, v);
   if (vgot < needed) return 0;

   double firstDelta = GRM_BarVolumeDelta(o[shift], c[shift], v[shift]);
   if (firstDelta == 0) return 0;
   int dir = (firstDelta > 0) ? 1 : -1;
   int streak = 0;
   for (int i = shift; i < needed; i++)
   {
      double d = GRM_BarVolumeDelta(o[i], c[i], v[i]);
      if ((d > 0 && dir > 0) || (d < 0 && dir < 0)) streak++;
      else break;
   }
   return dir * streak;
}

// Volume imbalance ratio: bull_vol / total_vol over N bars
double GRM_VolumeImbalanceRatio(const string sym, ENUM_TIMEFRAMES tf, int bars, int shift = 1)
{
   double o[], c[];
   long   v[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true); ArraySetAsSeries(v, true);
   int needed = bars + shift;
   if (CopyOpen(sym, tf, 0, needed, o)  < needed) return 0.5;
   if (CopyClose(sym, tf, 0, needed, c) < needed) return 0.5;
   int vgot = (int)CopyRealVolume(sym, tf, 0, needed, v);
   if (vgot < needed) vgot = (int)CopyTickVolume(sym, tf, 0, needed, v);
   if (vgot < needed) return 0.5;

   double bullVol = 0, totalVol = 0;
   for (int i = shift; i < shift + bars; i++)
   {
      totalVol += (double)v[i];
      if (c[i] > o[i]) bullVol += (double)v[i];
   }
   if (totalVol <= 0) return 0.5;
   return bullVol / totalVol;
}

//+------------------------------------------------------------------+
//| HIDDEN DIVERGENCE DETECTION                                      |
//| Hidden Bullish:  price Higher Low  + RSI  Lower Low  → BUY cont |
//| Hidden Bearish:  price Lower High  + RSI  Higher High → SELL cont|
//| Regular Bullish: price Lower Low   + RSI  Higher Low  → reversal |
//| Regular Bearish: price Higher High + RSI  Lower High  → reversal |
//+------------------------------------------------------------------+

// Find pivot low within shift..shift+lookback. Returns price and RSI at that bar.
bool GRM_FindPivotLow(const string sym, ENUM_TIMEFRAMES tf, int lookback, int startShift,
                      double &pivotPrice, double &pivotRSI, int &pivotBar,
                      int rsiPeriod = 14)
{
   double lo[];
   ArraySetAsSeries(lo, true);
   if (CopyLow(sym, tf, startShift, lookback, lo) < lookback) return false;

   // Find the lowest bar in range
   int minIdx = 0;
   for (int i = 1; i < lookback; i++)
      if (lo[i] < lo[minIdx]) minIdx = i;

   pivotPrice = lo[minIdx];
   pivotBar   = startShift + minIdx;

   double rBuf[]; ArraySetAsSeries(rBuf, true);
   int rh = iRSI(sym, tf, rsiPeriod, PRICE_CLOSE);
   if (rh == INVALID_HANDLE) return false;
   bool ok = (CopyBuffer(rh, 0, pivotBar, 1, rBuf) >= 1);
   IndicatorRelease(rh);
   if (!ok) return false;
   pivotRSI = rBuf[0];
   return true;
}

bool GRM_FindPivotHigh(const string sym, ENUM_TIMEFRAMES tf, int lookback, int startShift,
                       double &pivotPrice, double &pivotRSI, int &pivotBar,
                       int rsiPeriod = 14)
{
   double hi[];
   ArraySetAsSeries(hi, true);
   if (CopyHigh(sym, tf, startShift, lookback, hi) < lookback) return false;

   int maxIdx = 0;
   for (int i = 1; i < lookback; i++)
      if (hi[i] > hi[maxIdx]) maxIdx = i;

   pivotPrice = hi[maxIdx];
   pivotBar   = startShift + maxIdx;

   double rBuf[]; ArraySetAsSeries(rBuf, true);
   int rh = iRSI(sym, tf, rsiPeriod, PRICE_CLOSE);
   if (rh == INVALID_HANDLE) return false;
   bool ok = (CopyBuffer(rh, 0, pivotBar, 1, rBuf) >= 1);
   IndicatorRelease(rh);
   if (!ok) return false;
   pivotRSI = rBuf[0];
   return true;
}

// Detect hidden bullish divergence (continuation buy signal)
// Recent low (shift1) is HIGHER than prior low (shift2), but RSI recent < RSI prior
bool GRM_HiddenBullDiv(const string sym, ENUM_TIMEFRAMES tf,
                       int recentLookback = 5, int priorLookback = 15,
                       int rsiPeriod = 14, double minRSIDiff = 2.0)
{
   double p1, r1, p2, r2;
   int b1, b2;
   if (!GRM_FindPivotLow(sym, tf, recentLookback, 1, p1, r1, b1, rsiPeriod)) return false;
   if (!GRM_FindPivotLow(sym, tf, priorLookback, recentLookback + 2, p2, r2, b2, rsiPeriod)) return false;
   // Hidden bull: price HL (p1 > p2) but RSI LL (r1 < r2)
   return (p1 > p2 && r1 < r2 - minRSIDiff);
}

// Detect hidden bearish divergence (continuation sell signal)
bool GRM_HiddenBearDiv(const string sym, ENUM_TIMEFRAMES tf,
                       int recentLookback = 5, int priorLookback = 15,
                       int rsiPeriod = 14, double minRSIDiff = 2.0)
{
   double p1, r1, p2, r2;
   int b1, b2;
   if (!GRM_FindPivotHigh(sym, tf, recentLookback, 1, p1, r1, b1, rsiPeriod)) return false;
   if (!GRM_FindPivotHigh(sym, tf, priorLookback, recentLookback + 2, p2, r2, b2, rsiPeriod)) return false;
   // Hidden bear: price LH (p1 < p2) but RSI HH (r1 > r2)
   return (p1 < p2 && r1 > r2 + minRSIDiff);
}

// Detect regular bullish divergence (reversal buy signal)
bool GRM_RegularBullDiv(const string sym, ENUM_TIMEFRAMES tf,
                        int recentLookback = 5, int priorLookback = 15,
                        int rsiPeriod = 14, double minRSIDiff = 2.0)
{
   double p1, r1, p2, r2;
   int b1, b2;
   if (!GRM_FindPivotLow(sym, tf, recentLookback, 1, p1, r1, b1, rsiPeriod)) return false;
   if (!GRM_FindPivotLow(sym, tf, priorLookback, recentLookback + 2, p2, r2, b2, rsiPeriod)) return false;
   // Regular bull: price LL (p1 < p2) but RSI HL (r1 > r2)
   return (p1 < p2 && r1 > r2 + minRSIDiff);
}

// Detect regular bearish divergence (reversal sell signal)
bool GRM_RegularBearDiv(const string sym, ENUM_TIMEFRAMES tf,
                        int recentLookback = 5, int priorLookback = 15,
                        int rsiPeriod = 14, double minRSIDiff = 2.0)
{
   double p1, r1, p2, r2;
   int b1, b2;
   if (!GRM_FindPivotHigh(sym, tf, recentLookback, 1, p1, r1, b1, rsiPeriod)) return false;
   if (!GRM_FindPivotHigh(sym, tf, priorLookback, recentLookback + 2, p2, r2, b2, rsiPeriod)) return false;
   // Regular bear: price HH (p1 > p2) but RSI LH (r1 < r2)
   return (p1 > p2 && r1 < r2 - minRSIDiff);
}

//+------------------------------------------------------------------+
//| ATR RATIO: Short ATR / Long ATR (volatility regime detection)   |
//| >1.3 = high volatility expanding; <0.8 = low/compressed vol     |
//+------------------------------------------------------------------+
double GRM_ATRRatio(const string sym, ENUM_TIMEFRAMES tf,
                    int shortPeriod = 5, int longPeriod = 20, int shift = 1)
{
   double sB[], lB[];
   ArraySetAsSeries(sB, true); ArraySetAsSeries(lB, true);
   int hs = iATR(sym, tf, shortPeriod);
   int hl = iATR(sym, tf, longPeriod);
   if (hs == INVALID_HANDLE || hl == INVALID_HANDLE)
   {
      if (hs != INVALID_HANDLE) IndicatorRelease(hs);
      if (hl != INVALID_HANDLE) IndicatorRelease(hl);
      return 1.0;
   }
   double sv = (CopyBuffer(hs, 0, shift, 1, sB) >= 1) ? sB[0] : 0;
   double lv = (CopyBuffer(hl, 0, shift, 1, lB) >= 1) ? lB[0] : 0;
   IndicatorRelease(hs);
   IndicatorRelease(hl);
   if (lv <= 0) return 1.0;
   return sv / lv;
}

//+------------------------------------------------------------------+
//| ADX VALUE (avoid creating handle in tight loops)                |
//+------------------------------------------------------------------+
double GRM_GetADX(const string sym, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double buf[]; ArraySetAsSeries(buf, true);
   int h = iADX(sym, tf, period);
   if (h == INVALID_HANDLE) return 0;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 0;
   IndicatorRelease(h);
   return v;
}

// Returns +DI and -DI as well
double GRM_GetADXFull(const string sym, ENUM_TIMEFRAMES tf, int period, int shift,
                      double &plusDI, double &minusDI)
{
   double adxB[], plusB[], minusB[];
   ArraySetAsSeries(adxB, true); ArraySetAsSeries(plusB, true); ArraySetAsSeries(minusB, true);
   int h = iADX(sym, tf, period);
   if (h == INVALID_HANDLE) { plusDI = minusDI = 0; return 0; }
   double adx = (CopyBuffer(h, 0, shift, 1, adxB)  >= 1) ? adxB[0]  : 0;
   plusDI     = (CopyBuffer(h, 1, shift, 1, plusB)  >= 1) ? plusB[0]  : 0;
   minusDI    = (CopyBuffer(h, 2, shift, 1, minusB) >= 1) ? minusB[0] : 0;
   IndicatorRelease(h);
   return adx;
}

//+------------------------------------------------------------------+
//| IMPULSE DETECTION: measures the size of last directional move   |
//| Returns: positive for bull impulse, negative for bear impulse   |
//+------------------------------------------------------------------+
double GRM_LastImpulseSize(const string sym, ENUM_TIMEFRAMES tf,
                           int lookback = 20, int shift = 1)
{
   double hi[], lo[], c[];
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true); ArraySetAsSeries(c, true);
   if (CopyHigh(sym, tf, shift, lookback, hi) < lookback) return 0;
   if (CopyLow(sym, tf, shift, lookback, lo)  < lookback) return 0;
   if (CopyClose(sym, tf, shift, lookback, c) < lookback) return 0;

   double rangeHigh = hi[0], rangeLow = lo[0];
   for (int i = 1; i < lookback; i++)
   {
      if (hi[i] > rangeHigh) rangeHigh = hi[i];
      if (lo[i] < rangeLow)  rangeLow  = lo[i];
   }
   // Direction: if recent close > midpoint → bull impulse
   double mid = (rangeHigh + rangeLow) / 2.0;
   double move = rangeHigh - rangeLow;
   return (c[0] > mid) ? move : -move;
}

#endif
