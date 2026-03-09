//+------------------------------------------------------------------+
//|                                              Supertrend_Signals.mq5 |
//| Supertrend (ATR) con flechas de señal en cambio de tendencia     |
//| Uso: cualquier gráfico/timeframe. Señales intuitivas BUY/SELL.   |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   4

#property indicator_label1  "Supertrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue, clrOrangeRed
#property indicator_width1  2

#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_arrow2  233

#property indicator_label3  "Sell Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_arrow3  234

#property indicator_label4  ""
#property indicator_type4   DRAW_NONE

input group "=== Supertrend ==="
input int    InpATR_Period   = 10;    // Periodo ATR
input double InpATR_Mult     = 3.0;   // Multiplicador ATR

double bufSupertrend[];
double bufColor[];
double bufBuy[];
double bufSell[];
double bufATR[];

int g_atrHandle = INVALID_HANDLE;

int OnInit()
{
   SetIndexBuffer(0, bufSupertrend, INDICATOR_DATA);
   SetIndexBuffer(1, bufColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, bufBuy, INDICATOR_DATA);
   SetIndexBuffer(3, bufSell, INDICATOR_DATA);
   SetIndexBuffer(4, bufATR, INDICATOR_CALCULATIONS);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   IndicatorSetString(INDICATOR_SHORTNAME, "Supertrend(" + IntegerToString(InpATR_Period) + "," + DoubleToString(InpATR_Mult, 1) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   if (g_atrHandle == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < InpATR_Period + 5) return 0;
   if (CopyBuffer(g_atrHandle, 0, 0, rates_total, bufATR) < rates_total) return 0;

   ArraySetAsSeries(bufSupertrend, true);
   ArraySetAsSeries(bufColor, true);
   ArraySetAsSeries(bufBuy, true);
   ArraySetAsSeries(bufSell, true);
   ArraySetAsSeries(bufATR, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int start = (prev_calculated > 0) ? prev_calculated - 1 : rates_total - 1;
   if (start < 2) start = 2;

   for (int i = start; i >= 0; i--)
   {
      double hl2 = (high[i] + low[i]) / 2.0;
      double atr = bufATR[i];
      double basicUpper = hl2 + InpATR_Mult * atr;
      double basicLower = hl2 - InpATR_Mult * atr;

      double finalUpper = basicUpper;
      double finalLower = basicLower;
      if (i + 1 < rates_total)
      {
         double prevUpper = (high[i+1] + low[i+1]) / 2.0 + InpATR_Mult * bufATR[i+1];
         double prevLower = (high[i+1] + low[i+1]) / 2.0 - InpATR_Mult * bufATR[i+1];
         if (basicUpper < bufSupertrend[i+1] && bufColor[i+1] == 0)
            finalUpper = bufSupertrend[i+1];
         else if (basicUpper > bufSupertrend[i+1] && close[i+1] > bufSupertrend[i+1])
            finalUpper = prevUpper;
         if (basicLower > bufSupertrend[i+1] && bufColor[i+1] == 1)
            finalLower = bufSupertrend[i+1];
         else if (basicLower < bufSupertrend[i+1] && close[i+1] < bufSupertrend[i+1])
            finalLower = prevLower;
      }

      double st;
      int trend;
      if (i + 1 >= rates_total)
      {
         st = finalLower;
         trend = 1;
      }
      else
      {
         int prevTrend = (int)(bufColor[i+1] + 0.5);
         if (prevTrend == 0)
         {
            if (close[i] <= finalUpper) { st = finalUpper; trend = 0; }
            else { st = finalLower; trend = 1; }
         }
         else
         {
            if (close[i] >= finalLower) { st = finalLower; trend = 1; }
            else { st = finalUpper; trend = 0; }
         }
      }

      bufSupertrend[i] = st;
      bufColor[i] = (double)trend;
      bufBuy[i] = EMPTY_VALUE;
      bufSell[i] = EMPTY_VALUE;

      if (i + 1 < rates_total)
      {
         int prevTrend = (int)(bufColor[i+1] + 0.5);
         if (prevTrend == 0 && trend == 1)
            bufBuy[i] = low[i] - (bufATR[i] * 0.5);
         else if (prevTrend == 1 && trend == 0)
            bufSell[i] = high[i] + (bufATR[i] * 0.5);
      }
   }

   return rates_total;
}
