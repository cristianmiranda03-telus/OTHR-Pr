//+------------------------------------------------------------------+
//|                                                     RSI_Zones.mq5 |
//| RSI con zonas 30/70 y flechas en cruces. Señales claras.         |
//| Ventana separada. Sobrecarga = vender, sobreventa = comprar.    |
//+------------------------------------------------------------------+
#property copyright "OTHR Indicators"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "Overbought 70"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  1

#property indicator_label3  "Oversold 30"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLime
#property indicator_width3  1

#property indicator_label4  "Buy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_arrow4  233

#property indicator_label5  "Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_arrow5  234

input group "=== RSI ==="
input int InpRSI_Period = 14;   // Periodo RSI
input int InpOverbought = 70;   // Nivel sobrecompra
input int InpOversold   = 30;   // Nivel sobreventa
input bool InpShowSignals = true; // Mostrar flechas de señal

double bufRSI[];
double buf70[];
double buf30[];
double bufBuy[];
double bufSell[];

int g_rsiHandle = INVALID_HANDLE;

int OnInit()
{
   SetIndexBuffer(0, bufRSI, INDICATOR_DATA);
   SetIndexBuffer(1, buf70, INDICATOR_DATA);
   SetIndexBuffer(2, buf30, INDICATOR_DATA);
   SetIndexBuffer(3, bufBuy, INDICATOR_DATA);
   SetIndexBuffer(4, bufSell, INDICATOR_DATA);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);
   IndicatorSetString(INDICATOR_SHORTNAME, "RSI Zones(" + IntegerToString(InpRSI_Period) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, 1);
   IndicatorSetInteger(INDICATOR_LEVELS, 2);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, (double)InpOverbought);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, (double)InpOversold);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrRed);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrLime);

   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   if (g_rsiHandle == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if (rates_total < InpRSI_Period + 2) return 0;
   if (CopyBuffer(g_rsiHandle, 0, 0, rates_total, bufRSI) < rates_total) return 0;

   ArraySetAsSeries(bufRSI, true);

   for (int i = 0; i < rates_total; i++)
   {
      buf70[i] = (double)InpOverbought;
      buf30[i] = (double)InpOversold;
      bufBuy[i] = EMPTY_VALUE;
      bufSell[i] = EMPTY_VALUE;
   }

   if (InpShowSignals)
   {
      for (int i = 1; i < rates_total - 1; i++)
      {
         if (bufRSI[i-1] <= InpOversold && bufRSI[i] > InpOversold)
            bufBuy[i] = InpOversold - 5;
         if (bufRSI[i-1] >= InpOverbought && bufRSI[i] < InpOverbought)
            bufSell[i] = InpOverbought + 5;
      }
   }

   return rates_total;
}
