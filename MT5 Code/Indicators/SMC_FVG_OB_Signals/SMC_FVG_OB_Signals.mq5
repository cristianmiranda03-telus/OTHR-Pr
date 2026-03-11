//+------------------------------------------------------------------+
//| SMC_FVG_OB_Signals.mq5                                           |
//| Indicador: Fair Value Gap y Order Block (señales en grafico)     |
//| Compatible con Gold_AI_SMC_Wyckoff EAs                           |
//+------------------------------------------------------------------+
#property copyright "Gold AI SMC Wyckoff"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Bull FVG"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_arrow1  233

#property indicator_label2  "Bear FVG"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_arrow2  234

#property indicator_label3  "Bull OB"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrDodgerBlue
#property indicator_width3  2
#property indicator_arrow3  251

#property indicator_label4  "Bear OB"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrange
#property indicator_width4  2
#property indicator_arrow4  252

input int    InpATR_Period   = 14;
input double InpOB_MinBodyATR = 0.8;

double bufBullFVG[];
double bufBearFVG[];
double bufBullOB[];
double bufBearOB[];

int OnInit()
{
   SetIndexBuffer(0, bufBullFVG, INDICATOR_DATA);
   SetIndexBuffer(1, bufBearFVG, INDICATOR_DATA);
   SetIndexBuffer(2, bufBullOB, INDICATOR_DATA);
   SetIndexBuffer(3, bufBearOB, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "SMC FVG/OB");
   return INIT_SUCCEEDED;
}

bool DetectBullFVG(int i, const double &high[], const double &low[], int total)
{
   if (i < 2 || i >= total) return false;
   return (low[i-1] > high[i-2]);
}

bool DetectBearFVG(int i, const double &high[], const double &low[], int total)
{
   if (i < 2 || i >= total) return false;
   return (high[i-1] < low[i-2]);
}

bool DetectBullOB(int i, const double &open[], const double &close[], double atr, int total)
{
   if (i < 2 || i >= total) return false;
   if (atr <= 0) return false;
   if (close[i-2] <= open[i-2]) return false;
   if (close[i-1] >= open[i-1]) return false;
   return (MathAbs(close[i-2] - open[i-2]) >= atr * InpOB_MinBodyATR);
}

bool DetectBearOB(int i, const double &open[], const double &close[], double atr, int total)
{
   if (i < 2 || i >= total) return false;
   if (atr <= 0) return false;
   if (close[i-2] >= open[i-2]) return false;
   if (close[i-1] <= open[i-1]) return false;
   return (MathAbs(close[i-2] - open[i-2]) >= atr * InpOB_MinBodyATR);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < 10) return 0;
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if (start < 3) start = 3;

   double atrBuf[];
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   if (atrHandle == INVALID_HANDLE) return 0;
   if (CopyBuffer(atrHandle, 0, 0, rates_total, atrBuf) < rates_total)
      { IndicatorRelease(atrHandle); return 0; }

   for (int i = start; i < rates_total - 3; i++)
   {
      bufBullFVG[i] = EMPTY_VALUE;
      bufBearFVG[i] = EMPTY_VALUE;
      bufBullOB[i] = EMPTY_VALUE;
      bufBearOB[i] = EMPTY_VALUE;

      if (DetectBullFVG(i, high, low, rates_total))
         bufBullFVG[i] = low[i];
      if (DetectBearFVG(i, high, low, rates_total))
         bufBearFVG[i] = high[i];

      double atr = (i < ArraySize(atrBuf)) ? atrBuf[i] : 0;
      if (DetectBullOB(i, open, close, atr, rates_total))
         bufBullOB[i] = low[i];
      if (DetectBearOB(i, open, close, atr, rates_total))
         bufBearOB[i] = high[i];
   }
   IndicatorRelease(atrHandle);
   return rates_total;
}
