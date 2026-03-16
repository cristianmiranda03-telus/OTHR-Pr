//+------------------------------------------------------------------+
//| GOLD_Vol_Range_ZScore.mq5                                        |
//| Strategy  : Z-Score Estadistico de Reversion a la Media - RANGO  |
//| Asset     : XAUUSD | Timeframe: M5 | Session: Todas              |
//|                                                                  |
//| Concepto  :                                                      |
//|  El Z-Score mide cuantas desviaciones estandar esta el precio    |
//|  alejado de su media. Z = (precio - media) / desv_std            |
//|  En mercados que revierten a la media (rangos o correcciones):   |
//|  - Z-Score > +2.0 = precio estadisticamente muy alto (vender)    |
//|  - Z-Score < -2.0 = precio estadisticamente muy bajo (comprar)   |
//|  Esta estrategia es "matematicamente fundamentada" y es usada    |
//|  por traders algoritmicos/quants para scalping estadistico.       |
//|  El Oro es un activo que estadisticamente revierte en rangos,    |
//|  especialmente durante sesion asiatica y entre sesiones.         |
//|  Filtro adicional: solo opera si ADX < 30 (mercado no tendencial) |
//|                                                                  |
//| Magic: 110005                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile Z-Score Statistical Reversion - M5"

#include "..\Common\Scalping_Common.mqh"

input group "=== Z-Score Configuracion ==="
input int    InpZScore_Period    = 20;    // Periodo para calcular media y desv_std
input double InpZScore_EntryBuy  = -2.0;  // Z-Score para compra (oversold estadistico)
input double InpZScore_EntrySell = 2.0;   // Z-Score para venta (overbought estadistico)
input double InpZScore_Exit      = 0.5;   // Z-Score objetivo de salida (cerca de media)

input group "=== Filtro de Rango (ADX) ==="
input int    InpADX_Period       = 14;
input double InpADX_Max          = 30.0;  // ADX < 30 = mercado sin tendencia fuerte

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.4;
input double InpSL_ATR_Mult      = 1.8;
input double InpTP_ATR_Mult      = 1.5;  // TP conservador (reversion parcial)
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110005;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MaxScore = 1;      // Max trend score to allow range trade (0=flat, 1=loose)

CTrade   g_trade;
datetime g_lastBarM5 = 0;

//+------------------------------------------------------------------+
//| Calcula el Z-Score del precio actual respecto a media movil       |
//+------------------------------------------------------------------+
double GetZScore(int period, int shift = 1)
{
   // Media de los ultimos N cierres
   double sum = 0;
   for (int i = shift; i < shift + period; i++)
      sum += SC_Close(_Symbol, PERIOD_M5, i);
   double mean = sum / period;

   // Desviacion estandar
   double sumSq = 0;
   for (int i = shift; i < shift + period; i++)
   {
      double diff = SC_Close(_Symbol, PERIOD_M5, i) - mean;
      sumSq += diff * diff;
   }
   double stdDev = MathSqrt(sumSq / period);
   if (stdDev <= 0) return 0;

   double currentClose = SC_Close(_Symbol, PERIOD_M5, shift);
   return (currentClose - mean) / stdDev;
}

double GetADX(int period, int shift = 1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   int h = iADX(_Symbol, PERIOD_M5, period);
   if (h == INVALID_HANDLE) return 50;
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 50;
   IndicatorRelease(h);
   return v;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_Vol_Range_ZScore iniciado | Periodo Z=", InpZScore_Period, " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_RangeOK(_Symbol, InpMTF_MaxScore)) return;

   double z    = GetZScore(InpZScore_Period, 1);
   double adx  = GetADX(InpADX_Period, 1);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   // Solo opera en rango (sin tendencia fuerte)
   bool isRange = (adx < InpADX_Max);
   int  digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (isRange && z <= InpZScore_EntryBuy && SC_CountPositions(POSITION_TYPE_BUY, InpMagic) == 0)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_ZScore_BUY"))
         Print("COMPRA Z-Score | z=", z, " | adx=", adx);
   }
   else if (isRange && z >= InpZScore_EntrySell && SC_CountPositions(POSITION_TYPE_SELL, InpMagic) == 0)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_ZScore_SELL"))
         Print("VENTA Z-Score | z=", z, " | adx=", adx);
   }
}
