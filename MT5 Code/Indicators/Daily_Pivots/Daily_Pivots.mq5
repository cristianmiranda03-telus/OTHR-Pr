//+------------------------------------------------------------------+
//|                                                  Daily_Pivots.mq5 |
//| Pivot Points clásicos del día anterior. Sin lag, niveles clave.  |
//| P, R1, R2, S1, S2 para operar rebotes y rupturas.                |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "Pivot"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  2

#property indicator_label2  "R1"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_width2  1

#property indicator_label3  "R2"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGreen
#property indicator_width3  1

#property indicator_label4  "S1"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrangeRed
#property indicator_width4  1

#property indicator_label5  "S2"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_width5  1

input group "=== Pivot Points ==="
input int  InpSessionShift = 0;   // Desplazamiento sesión (horas)
input bool InpDailySession  = true; // Usar cierre diario (true) o sesión 24h

double bufP[], bufR1[], bufR2[], bufS1[], bufS2[];

int OnInit()
{
   SetIndexBuffer(0, bufP, INDICATOR_DATA);
   SetIndexBuffer(1, bufR1, INDICATOR_DATA);
   SetIndexBuffer(2, bufR2, INDICATOR_DATA);
   SetIndexBuffer(3, bufS1, INDICATOR_DATA);
   SetIndexBuffer(4, bufS2, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "Daily Pivots");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < 2) return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(bufP, true);
   ArraySetAsSeries(bufR1, true);
   ArraySetAsSeries(bufR2, true);
   ArraySetAsSeries(bufS1, true);
   ArraySetAsSeries(bufS2, true);

   double prevH = 0, prevL = 0, prevC = 0;
   double lastH = 0, lastL = 0, lastC = 0;
   int prevDay = -1;
   int dayStartIdx = rates_total - 1;

   for (int i = rates_total - 1; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int d = dt.year * 10000 + dt.mon * 100 + dt.day;

      if (d != prevDay)
      {
         if (prevDay >= 0 && lastH > 0)
         {
            double P = (lastH + lastL + lastC) / 3.0;
            double R1 = 2.0 * P - lastL;
            double R2 = P + (lastH - lastL);
            double S1 = 2.0 * P - lastH;
            double S2 = P - (lastH - lastL);
            for (int j = dayStartIdx; j > i; j--)
            {
               bufP[j] = P;
               bufR1[j] = R1;
               bufR2[j] = R2;
               bufS1[j] = S1;
               bufS2[j] = S2;
            }
         }
         lastH = prevH;
         lastL = prevL;
         lastC = prevC;
         prevDay = d;
         dayStartIdx = i;
         prevH = high[i];
         prevL = low[i];
         prevC = close[i];
      }
      else
      {
         if (high[i] > prevH) prevH = high[i];
         if (low[i] < prevL) prevL = low[i];
         prevC = close[i];
      }
   }

   if (prevDay >= 0 && lastH > 0)
   {
      double P = (lastH + lastL + lastC) / 3.0;
      double R1 = 2.0 * P - lastL;
      double R2 = P + (lastH - lastL);
      double S1 = 2.0 * P - lastH;
      double S2 = P - (lastH - lastL);
      for (int j = dayStartIdx; j >= 0; j--)
      {
         bufP[j] = P;
         bufR1[j] = R1;
         bufR2[j] = R2;
         bufS1[j] = S1;
         bufS2[j] = S2;
      }
   }

   return rates_total;
}
