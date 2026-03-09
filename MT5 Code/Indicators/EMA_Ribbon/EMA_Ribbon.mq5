//+------------------------------------------------------------------+
//|                                                   EMA_Ribbon.mq5 |
//| Cinta de EMAs para ver tendencia de un vistazo. Colores intuitivos.|
//| Precio encima de la cinta = alcista; debajo = bajista.           |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   6

#property indicator_label1  "EMA 9"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "EMA 21"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_width2  1

#property indicator_label3  "EMA 50"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  1

#property indicator_label4  "EMA 100"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_width4  1

#property indicator_label5  "EMA 200"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_width5  1

#property indicator_label6  "Trend Zone"
#property indicator_type6   DRAW_FILLING
#property indicator_color6  clrLime, clrRed
#property indicator_width6  1

input group "=== EMA Ribbon ==="
input int InpEMA1 = 9;    // EMA rápida
input int InpEMA2 = 21;   // EMA
input int InpEMA3 = 50;   // EMA
input int InpEMA4 = 100;  // EMA
input int InpEMA5 = 200;  // EMA lenta

double buf1[], buf2[], buf3[], buf4[], buf5[], bufZoneUp[], bufZoneDn[];

int g_h1, g_h2, g_h3, g_h4, g_h5;

int OnInit()
{
   SetIndexBuffer(0, buf1, INDICATOR_DATA);
   SetIndexBuffer(1, buf2, INDICATOR_DATA);
   SetIndexBuffer(2, buf3, INDICATOR_DATA);
   SetIndexBuffer(3, buf4, INDICATOR_DATA);
   SetIndexBuffer(4, buf5, INDICATOR_DATA);
   SetIndexBuffer(5, bufZoneUp, INDICATOR_DATA);
   SetIndexBuffer(6, bufZoneDn, INDICATOR_DATA);
   PlotIndexSetInteger(5, PLOT_FILLING, 0, 4);
   IndicatorSetString(INDICATOR_SHORTNAME, "EMA Ribbon");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_h1 = iMA(_Symbol, PERIOD_CURRENT, InpEMA1, 0, MODE_EMA, PRICE_CLOSE);
   g_h2 = iMA(_Symbol, PERIOD_CURRENT, InpEMA2, 0, MODE_EMA, PRICE_CLOSE);
   g_h3 = iMA(_Symbol, PERIOD_CURRENT, InpEMA3, 0, MODE_EMA, PRICE_CLOSE);
   g_h4 = iMA(_Symbol, PERIOD_CURRENT, InpEMA4, 0, MODE_EMA, PRICE_CLOSE);
   g_h5 = iMA(_Symbol, PERIOD_CURRENT, InpEMA5, 0, MODE_EMA, PRICE_CLOSE);
   if (g_h1 == INVALID_HANDLE || g_h2 == INVALID_HANDLE || g_h3 == INVALID_HANDLE ||
       g_h4 == INVALID_HANDLE || g_h5 == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_h1 != INVALID_HANDLE) IndicatorRelease(g_h1);
   if (g_h2 != INVALID_HANDLE) IndicatorRelease(g_h2);
   if (g_h3 != INVALID_HANDLE) IndicatorRelease(g_h3);
   if (g_h4 != INVALID_HANDLE) IndicatorRelease(g_h4);
   if (g_h5 != INVALID_HANDLE) IndicatorRelease(g_h5);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < InpEMA5) return 0;
   if (CopyBuffer(g_h1, 0, 0, rates_total, buf1) < rates_total) return 0;
   if (CopyBuffer(g_h2, 0, 0, rates_total, buf2) < rates_total) return 0;
   if (CopyBuffer(g_h3, 0, 0, rates_total, buf3) < rates_total) return 0;
   if (CopyBuffer(g_h4, 0, 0, rates_total, buf4) < rates_total) return 0;
   if (CopyBuffer(g_h5, 0, 0, rates_total, buf5) < rates_total) return 0;

   ArraySetAsSeries(buf1, true);
   ArraySetAsSeries(buf2, true);
   ArraySetAsSeries(buf3, true);
   ArraySetAsSeries(buf4, true);
   ArraySetAsSeries(buf5, true);

   for (int i = 0; i < rates_total; i++)
   {
      bufZoneUp[i] = MathMax(buf1[i], buf5[i]);
      bufZoneDn[i] = MathMin(buf1[i], buf5[i]);
   }

   return rates_total;
}
