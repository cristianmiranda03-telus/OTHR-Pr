//+------------------------------------------------------------------+
//|                                                    VWAP_Bands.mq5 |
//| VWAP + bandas de desviación estándar. Sin lag, ideal intraday.   |
//| Señales: precio sobre VWAP = sesión alcista, bajo = bajista.     |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  2

#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1

#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1

#property indicator_label4  "Upper 2"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGray
#property indicator_width4  1

#property indicator_label5  "Lower 2"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGray
#property indicator_width5  1

input group "=== VWAP ==="
input int    InpStdDevPeriod = 20;    // Periodo para desviación estándar
input double InpStdMult1     = 2.0;   // Multiplicador banda 1
input double InpStdMult2     = 3.0;   // Multiplicador banda 2
input ENUM_APPLIED_VOLUME InpVolume = VOLUME_TICK; // Volumen

double bufVWAP[];
double bufUpper1[];
double bufLower1[];
double bufUpper2[];
double bufLower2[];

double g_cumTypicalVol[], g_cumVol[], g_sqTypical[];

int OnInit()
{
   SetIndexBuffer(0, bufVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, bufUpper1, INDICATOR_DATA);
   SetIndexBuffer(2, bufLower1, INDICATOR_DATA);
   SetIndexBuffer(3, bufUpper2, INDICATOR_DATA);
   SetIndexBuffer(4, bufLower2, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "VWAP Bands");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   ArrayResize(g_cumTypicalVol, 0);
   ArrayResize(g_cumVol, 0);
   ArrayResize(g_sqTypical, 0);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < 2) return 0;

   long vol[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);
   if (CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, rates_total, vol) < rates_total)
   {
      ArrayResize(vol, rates_total);
      for (int k = 0; k < rates_total; k++) vol[k] = 1;
   }
   else
      ArraySetAsSeries(vol, true);

   ArraySetAsSeries(bufVWAP, true);
   ArraySetAsSeries(bufUpper1, true);
   ArraySetAsSeries(bufLower1, true);
   ArraySetAsSeries(bufUpper2, true);
   ArraySetAsSeries(bufLower2, true);

   ArrayResize(g_cumTypicalVol, rates_total);
   ArrayResize(g_cumVol, rates_total);
   ArrayResize(g_sqTypical, rates_total);
   ArraySetAsSeries(g_cumTypicalVol, true);
   ArraySetAsSeries(g_cumVol, true);
   ArraySetAsSeries(g_sqTypical, true);

   int dayPrev = -1;

   for (int i = rates_total - 1; i >= 0; i--)
   {
      double typical = (high[i] + low[i] + close[i]) / 3.0;
      long v = (InpVolume == VOLUME_REAL) ? (long)volume[i] : (long)vol[i];
      if (v <= 0) v = 1;

      int dayCur = (int)(time[i] / 86400);
      if (dayCur != dayPrev)
      {
         g_cumTypicalVol[i] = typical * (double)v;
         g_cumVol[i] = (double)v;
         g_sqTypical[i] = typical * typical * (double)v;
      }
      else
      {
         int iNext = i + 1;
         if (iNext < rates_total)
         {
            g_cumTypicalVol[i] = g_cumTypicalVol[iNext] + typical * (double)v;
            g_cumVol[i] = g_cumVol[iNext] + (double)v;
            g_sqTypical[i] = g_sqTypical[iNext] + typical * typical * (double)v;
         }
         else
         {
            g_cumTypicalVol[i] = typical * (double)v;
            g_cumVol[i] = (double)v;
            g_sqTypical[i] = typical * typical * (double)v;
         }
      }
      dayPrev = dayCur;

      if (g_cumVol[i] > 0)
      {
         bufVWAP[i] = g_cumTypicalVol[i] / g_cumVol[i];
         double avgSq = g_sqTypical[i] / g_cumVol[i];
         double variance = avgSq - bufVWAP[i] * bufVWAP[i];
         if (variance < 0) variance = 0;
         double std = MathSqrt(variance);
         bufUpper1[i] = bufVWAP[i] + InpStdMult1 * std;
         bufLower1[i] = bufVWAP[i] - InpStdMult1 * std;
         bufUpper2[i] = bufVWAP[i] + InpStdMult2 * std;
         bufLower2[i] = bufVWAP[i] - InpStdMult2 * std;
      }
      else
      {
         bufVWAP[i] = (i + 1 < rates_total) ? bufVWAP[i+1] : typical;
         bufUpper1[i] = bufVWAP[i];
         bufLower1[i] = bufVWAP[i];
         bufUpper2[i] = bufVWAP[i];
         bufLower2[i] = bufVWAP[i];
      }
   }

   return rates_total;
}
