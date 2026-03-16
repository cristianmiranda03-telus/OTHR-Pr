//+------------------------------------------------------------------+
//| GOLD_Vol_Bear_ROC_Momentum.mq5                                   |
//| Strategy  : Rate of Change (ROC) Momentum BAJISTA en volatilidad |
//| Asset     : XAUUSD | Timeframe: M5 | Session: London + NY        |
//|                                                                  |
//| Concepto  :                                                      |
//|  Complementario de GOLD_Vol_Bull_ROC_Momentum.                  |
//|  Cuando el ROC es negativamente intenso (caida rapida del precio) |
//|  en alta volatilidad + tendencia bajista M5 = venta de momentum.  |
//|  Ideal para capturar la aceleracion inicial de movimientos         |
//|  bajistas del Oro post-datos economicos (inflacion US, NFP, etc.) |
//|                                                                  |
//| Magic: 110002                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile ROC Momentum Bear - M5"

#include "..\Common\Scalping_Common.mqh"

input group "=== Rate of Change (ROC) Configuracion ==="
input int    InpROC_Period       = 10;
input int    InpROC_Fast_Period  = 5;
input double InpROC_Threshold    = -0.15;  // ROC maximo negativo para señal bajista
input double InpATR_VolMult      = 1.2;
input int    InpATR_SMA_Bars     = 20;

input group "=== Filtros de Tendencia ==="
input int    InpEMA_Fast         = 21;
input int    InpEMA_Slow         = 50;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 22.0;  // RSI minimo (no sobrevendido ya)
input double InpRSI_Max          = 48.0;  // RSI maximo para venta

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.2;
input double InpTP_ATR_Mult      = 2.5;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110002;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bearish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBarM5 = 0;

double GetROC(int period, int shift = 1)
{
   double c = SC_Close(_Symbol, PERIOD_M5, shift);
   double p = SC_Close(_Symbol, PERIOD_M5, shift + period);
   return (p > 0) ? ((c - p) / p) * 100.0 : 0;
}

double GetATR_Avg(int bars)
{
   double sum = 0;
   for (int i = 2; i <= bars + 1; i++)
      sum += SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, i);
   return (bars > 0) ? sum / bars : 0;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BearOK(_Symbol, InpMTF_MinScore)) return;

   double roc10  = GetROC(InpROC_Period, 1);
   double roc5   = GetROC(InpROC_Fast_Period, 1);
   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   bool highVol   = (avgATR <= 0 || atr >= avgATR * InpATR_VolMult);
   bool rocBear   = (roc10 <= InpROC_Threshold) && (roc5 < 0);
   bool downtrend = (ema21 < ema50);
   bool rsiOK     = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);

   if (highVol && rocBear && downtrend && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Vol_ROC_Bear"))
         Print("VENTA ROC Momentum | roc10=", roc10, "% | roc5=", roc5, "%");
   }
}
