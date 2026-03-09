//+------------------------------------------------------------------+
//|                                              Hull_MA_Signals.mq5 |
//| Hull Moving Average - bajo lag, señales de cruce con precio.    |
//| HMA = WMA(2*WMA(n/2) - WMA(n), sqrt(n)). Flechas en cruces.     |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Hull MA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue, clrOrangeRed
#property indicator_width1  2

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_arrow2  233

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_arrow3  234

#property indicator_label4  ""
#property indicator_type4   DRAW_NONE

input group "=== Hull MA ==="
input int InpPeriod = 20;   // Periodo HMA

double bufHMA[];
double bufColor[];
double bufBuy[];
double bufSell[];

static double WMA(const double &arr[], int len, int idx)
{
   double sum = 0, wsum = 0;
   for (int i = 0; i < len && (idx + i) < ArraySize(arr); i++)
   {
      double w = (double)(len - i);
      sum += arr[idx + i] * w;
      wsum += w;
   }
   return (wsum > 0) ? sum / wsum : arr[idx];
}

int OnInit()
{
   SetIndexBuffer(0, bufHMA, INDICATOR_DATA);
   SetIndexBuffer(1, bufColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, bufBuy, INDICATOR_DATA);
   SetIndexBuffer(3, bufSell, INDICATOR_DATA);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   IndicatorSetString(INDICATOR_SHORTNAME, "Hull MA(" + IntegerToString(InpPeriod) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   int period = InpPeriod;
   if (period < 2) period = 2;
   int half = (int)MathFloor(period / 2.0);
   int sqrtPeriod = (int)MathMax(2, MathFloor(MathSqrt((double)period)));

   if (rates_total < period + sqrtPeriod + 5) return 0;

   double rawHMA[];
   ArrayResize(rawHMA, rates_total);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(rawHMA, true);
   ArraySetAsSeries(bufHMA, true);
   ArraySetAsSeries(bufColor, true);
   ArraySetAsSeries(bufBuy, true);
   ArraySetAsSeries(bufSell, true);

   for (int i = 0; i < rates_total; i++)
      rawHMA[i] = 2.0 * WMA(close, half, i) - WMA(close, period, i);

   for (int i = 0; i < rates_total; i++)
   {
      bufHMA[i] = WMA(rawHMA, sqrtPeriod, i);
      bufColor[i] = (close[i] >= bufHMA[i]) ? 0 : 1;
      bufBuy[i] = EMPTY_VALUE;
      bufSell[i] = EMPTY_VALUE;
   }

   for (int i = 1; i < rates_total - 1; i++)
   {
      bool crossUp = (close[i] > bufHMA[i] && close[i+1] <= bufHMA[i+1]);
      bool crossDn = (close[i] < bufHMA[i] && close[i+1] >= bufHMA[i+1]);
      if (crossUp) bufBuy[i] = low[i] - (high[i] - low[i]) * 0.2;
      if (crossDn) bufSell[i] = high[i] + (high[i] - low[i]) * 0.2;
   }

   return rates_total;
}
