//+------------------------------------------------------------------+
//| JumpEntropy_Regime.mq5                                          |
//| Régimen: salto (|return| > theta*sigma) + entropía signos       |
//| Ventana separada: histograma jump strength + línea entropía      |
//+------------------------------------------------------------------+
#property copyright "OTHR - Jump Entropy Regime"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   2

#property indicator_label1  "Jump strength"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrOrange
#property indicator_width1  2

#property indicator_label2  "Entropy 0-1"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue

input int    InpSigmaPeriod  = 40;
input double InpJumpTheta    = 3.5;
input int    InpEntropyBars  = 24;
input double InpEntropyHigh  = 0.92;

double JumpBuffer[];
double EntropyBuffer[];
double JumpFlag[];
double Placeholder[];

int OnInit()
{
   SetIndexBuffer(0, JumpBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, EntropyBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, JumpFlag, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, Placeholder, INDICATOR_CALCULATIONS);
   IndicatorSetString(INDICATOR_SHORTNAME, "JumpEntropy Regime");
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   ArrayInitialize(JumpBuffer, 0.0);
   ArrayInitialize(EntropyBuffer, 0.0);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minBars = MathMax(InpSigmaPeriod, InpEntropyBars) + 3;
   if (rates_total < minBars) return 0;

   int start;
   if (prev_calculated == 0)
      start = minBars;
   else
      start = MathMax(minBars, prev_calculated - 1);

   for (int i = start; i < rates_total; i++)
   {
      JumpBuffer[i] = 0;
      EntropyBuffer[i] = 0;
      JumpFlag[i] = 0;

      if (close[i] <= 0 || close[i - 1] <= 0) continue;
      double r = MathLog(close[i] / close[i - 1]);

      double sum = 0, sumsq = 0;
      int n = 0;
      for (int k = 1; k <= InpSigmaPeriod && (i - k) >= 0; k++)
      {
         if (close[i - k] <= 0 || close[i - k - 1] <= 0) continue;
         double rk = MathLog(close[i - k] / close[i - k - 1]);
         sum += rk;
         sumsq += rk * rk;
         n++;
      }
      double sigma = 0;
      if (n > 2)
      {
         double mean = sum / n;
         double var = (sumsq / n) - mean * mean;
         if (var > 0) sigma = MathSqrt(var);
      }
      if (sigma > 1e-12 && MathAbs(r) > InpJumpTheta * sigma)
      {
         JumpFlag[i] = 1;
         JumpBuffer[i] = MathAbs(r) / sigma;
      }

      int up = 0, down = 0, flat = 0;
      for (int b = 0; b < InpEntropyBars && (i - b) >= 0; b++)
      {
         int j = i - b;
         double range = high[j] - low[j];
         if (range < 1e-9) { flat++; continue; }
         double o = open[j], c = close[j];
         if (MathAbs(c - o) < range * 0.08) { flat++; continue; }
         if (c > o) up++;
         else if (c < o) down++;
         else flat++;
      }
      int tot = up + down + flat;
      double H = 0;
      if (tot > 0)
      {
         if (up > 0)   H -= (double)up / tot * MathLog((double)up / tot);
         if (down > 0) H -= (double)down / tot * MathLog((double)down / tot);
         if (flat > 0) H -= (double)flat / tot * MathLog((double)flat / tot);
         H /= MathLog(3.0);
      }
      EntropyBuffer[i] = H;
   }
   return rates_total;
}
