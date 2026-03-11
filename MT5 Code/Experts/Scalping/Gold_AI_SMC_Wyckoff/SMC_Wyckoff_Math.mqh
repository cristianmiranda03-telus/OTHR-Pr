//+------------------------------------------------------------------+
//| SMC_Wyckoff_Math.mqh                                             |
//| Smart Money, Wyckoff, Money Flow - fundamentos matematicos       |
//| Para EAs Gold scalping en Gold_AI_SMC_Wyckoff                    |
//+------------------------------------------------------------------+
#ifndef SMC_WYCKOFF_MATH_MQH
#define SMC_WYCKOFF_MATH_MQH

//--- FVG (Fair Value Gap): desequilibrio 3 velas
// Bullish FVG: Low[1] > High[3]. Bearish FVG: High[1] < Low[3]

bool SMC_DetectBullFVG(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double &gapTop, double &gapBottom)
{
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(sym, tf, shift, 5, h) < 5 || CopyLow(sym, tf, shift, 5, l) < 5)
      return false;
   if (l[1] <= h[2]) return false;
   gapTop = l[1];
   gapBottom = h[2];
   return true;
}

bool SMC_DetectBearFVG(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double &gapTop, double &gapBottom)
{
   double h[], l[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyHigh(sym, tf, shift, 5, h) < 5 || CopyLow(sym, tf, shift, 5, l) < 5)
      return false;
   if (h[1] >= l[2]) return false;
   gapTop = l[2];
   gapBottom = h[1];
   return true;
}

//--- Order Block: ultima vela opuesta antes de impulso
bool SMC_BullOrderBlock(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double atr, double minBodyATR, double &obHigh, double &obLow)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(sym, tf, shift, 6, o) < 6 || CopyClose(sym, tf, shift, 6, c) < 6) return false;
   if (CopyHigh(sym, tf, shift, 6, h) < 6 || CopyLow(sym, tf, shift, 6, l) < 6) return false;
   if (atr <= 0) return false;
   if (c[2] <= o[2]) return false;
   if (c[1] >= o[1]) return false;
   if (MathAbs(c[2] - o[2]) < atr * minBodyATR) return false;
   obHigh = h[1];
   obLow = l[1];
   return true;
}

bool SMC_BearOrderBlock(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double atr, double minBodyATR, double &obHigh, double &obLow)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(sym, tf, shift, 6, o) < 6 || CopyClose(sym, tf, shift, 6, c) < 6) return false;
   if (CopyHigh(sym, tf, shift, 6, h) < 6 || CopyLow(sym, tf, shift, 6, l) < 6) return false;
   if (atr <= 0) return false;
   if (c[2] >= o[2]) return false;
   if (c[1] <= o[1]) return false;
   if (MathAbs(c[2] - o[2]) < atr * minBodyATR) return false;
   obHigh = h[1];
   obLow = l[1];
   return true;
}

//--- Wyckoff Spring / Upthrust
bool Wyckoff_Spring(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double rangeHigh, double rangeLow, double &closeBack)
{
   double c[], l[];
   ArraySetAsSeries(c, true); ArraySetAsSeries(l, true);
   if (CopyClose(sym, tf, shift, 1, c) < 1 || CopyLow(sym, tf, shift, 1, l) < 1) return false;
   if (l[0] >= rangeLow) return false;
   if (c[0] <= rangeLow) return false;
   closeBack = c[0];
   return (c[0] > rangeLow && c[0] < rangeHigh);
}

bool Wyckoff_Upthrust(const string sym, ENUM_TIMEFRAMES tf, int shift,
   double rangeHigh, double rangeLow, double &closeBack)
{
   double c[], h[];
   ArraySetAsSeries(c, true); ArraySetAsSeries(h, true);
   if (CopyClose(sym, tf, shift, 1, c) < 1 || CopyHigh(sym, tf, shift, 1, h) < 1) return false;
   if (h[0] <= rangeHigh) return false;
   if (c[0] >= rangeHigh) return false;
   closeBack = c[0];
   return (c[0] < rangeHigh && c[0] > rangeLow);
}

//--- Liquidity sweep
bool SMC_SweepHighs(const string sym, ENUM_TIMEFRAMES tf, int shift, int lookback,
   double &sweepLevel)
{
   double h[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(c, true);
   if (CopyHigh(sym, tf, shift, lookback + 2, h) < lookback + 2) return false;
   if (CopyClose(sym, tf, shift, lookback + 2, c) < lookback + 2) return false;
   double prevHH = h[1];
   for (int i = 2; i < lookback; i++)
      if (h[i] > prevHH) prevHH = h[i];
   if (h[0] <= prevHH) return false;
   if (c[0] >= prevHH) return false;
   sweepLevel = prevHH;
   return true;
}

bool SMC_SweepLows(const string sym, ENUM_TIMEFRAMES tf, int shift, int lookback,
   double &sweepLevel)
{
   double l[], c[];
   ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if (CopyLow(sym, tf, shift, lookback + 2, l) < lookback + 2) return false;
   if (CopyClose(sym, tf, shift, lookback + 2, c) < lookback + 2) return false;
   double prevLL = l[1];
   for (int i = 2; i < lookback; i++)
      if (l[i] < prevLL) prevLL = l[i];
   if (l[0] >= prevLL) return false;
   if (c[0] <= prevLL) return false;
   sweepLevel = prevLL;
   return true;
}

//--- MFI (Money Flow Index)
double Math_MFI(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int n = period + 1;
   double h[], l[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if (CopyHigh(sym, tf, shift, n, h) < n || CopyLow(sym, tf, shift, n, l) < n ||
       CopyClose(sym, tf, shift, n, c) < n) return 50;
   long vol[];
   ArraySetAsSeries(vol, true);
   int vgot = (int)CopyRealVolume(sym, tf, shift, n, vol);
   if (vgot < n) { vgot = (int)CopyTickVolume(sym, tf, shift, n, vol); if (vgot < n) return 50; }
   double posSum = 0, negSum = 0;
   for (int i = 1; i < n; i++)
   {
      double typical = (h[i] + l[i] + c[i]) / 3.0;
      double prevTypical = (h[i+1] + l[i+1] + c[i+1]) / 3.0;
      double raw = typical * (double)vol[i];
      if (typical > prevTypical) posSum += raw;
      else if (typical < prevTypical) negSum += raw;
   }
   if (negSum <= 0) return (posSum > 0) ? 80 : 50;
   return 100.0 - 100.0 / (1.0 + posSum / negSum);
}

double Math_ZScore(double price, double mean, double stdDev)
{
   if (stdDev <= 0) return 0;
   return (price - mean) / stdDev;
}

double Math_RealizedVol(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double c[];
   ArraySetAsSeries(c, true);
   if (CopyClose(sym, tf, shift, period + 2, c) < period + 2) return 0;
   double sum = 0, sumSq = 0;
   int n = 0;
   for (int i = 0; i < period; i++)
   {
      if (c[i+1] <= 0) continue;
      double r = MathLog(c[i] / c[i+1]);
      sum += r;
      sumSq += r * r;
      n++;
   }
   if (n < 3) return 0;
   double mu = sum / n;
   double var = (sumSq / n) - mu * mu;
   return (var > 0) ? MathSqrt(var) : 0;
}

double Math_EntropySigns(const string sym, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double o[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(sym, tf, shift, period, o) < period || CopyClose(sym, tf, shift, period, c) < period)
      return 0.5;
   int up = 0, down = 0, flat = 0;
   for (int i = 0; i < period; i++)
   {
      if (c[i] > o[i]) up++;
      else if (c[i] < o[i]) down++;
      else flat++;
   }
   int tot = up + down + flat;
   if (tot == 0) return 0.5;
   double H = 0;
   if (up > 0)   H -= (double)up / tot * MathLog((double)up / tot);
   if (down > 0) H -= (double)down / tot * MathLog((double)down / tot);
   if (flat > 0) H -= (double)flat / tot * MathLog((double)flat / tot);
   return H / MathLog(3.0);
}

#endif
