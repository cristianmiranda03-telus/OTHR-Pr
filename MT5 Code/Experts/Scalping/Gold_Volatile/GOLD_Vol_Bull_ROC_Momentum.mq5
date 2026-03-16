//+------------------------------------------------------------------+
//| GOLD_Vol_Bull_ROC_Momentum.mq5                                   |
//| Strategy  : Rate of Change (ROC) Momentum ALCISTA en volatilidad |
//| Asset     : XAUUSD | Timeframe: M5 | Session: London + NY        |
//|                                                                  |
//| Concepto  :                                                      |
//|  El Rate of Change (ROC) mide la velocidad del movimiento del    |
//|  precio: ROC = (Close_actual - Close_n_periodos_atras) / Close_n  |
//|  x 100. Es una medida de momentum puro.                          |
//|  En momentos de alta volatilidad del Oro (durante noticias,       |
//|  apertura de mercados, datos economicos), el ROC supera un        |
//|  umbral significativo que indica impulso genuino.                 |
//|  Estrategia:                                                     |
//|  1. ROC de 10 barras > InpROC_Threshold (momentum alcista fuerte) |
//|  2. ROC de 5 barras tambien positivo (momentum reciente confirma) |
//|  3. EMA21 > EMA50 (tendencia M5 alcista)                        |
//|  4. ATR > SMA(ATR) * 1.2 (alta volatilidad activa)              |
//|  Esta estrategia opera con frecuencia en sesiones volatiles.     |
//|                                                                  |
//| Magic: 110001                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile ROC Momentum Bull - M5"

#include "..\Common\Scalping_Common.mqh"

input group "=== Rate of Change (ROC) Configuracion ==="
input int    InpROC_Period       = 10;    // Periodo principal del ROC
input int    InpROC_Fast_Period  = 5;     // ROC rapido para confirmacion
input double InpROC_Threshold    = 0.15;  // ROC minimo (%) para señal alcista en XAUUSD
input double InpATR_VolMult      = 1.2;   // ATR debe ser > N x promedio (alta volatilidad)
input int    InpATR_SMA_Bars     = 20;    // Barras para promedio del ATR

input group "=== Filtros de Tendencia ==="
input int    InpEMA_Fast         = 21;
input int    InpEMA_Slow         = 50;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 52.0;  // RSI minimo (evitar comprar en caida)
input double InpRSI_Max          = 78.0;  // RSI maximo (no comprar sobrecomprado)

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
input int    InpMagic            = 110001;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bullish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBarM5 = 0;

//+------------------------------------------------------------------+
//| Calcula Rate of Change (ROC) en porcentaje                       |
//+------------------------------------------------------------------+
double GetROC(int period, int shift = 1)
{
   double current = SC_Close(_Symbol, PERIOD_M5, shift);
   double past    = SC_Close(_Symbol, PERIOD_M5, shift + period);
   if (past <= 0) return 0;
   return ((current - past) / past) * 100.0;
}

//+------------------------------------------------------------------+
//| ATR promedio de N barras                                         |
//+------------------------------------------------------------------+
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
   Print("GOLD_Vol_Bull_ROC_Momentum iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BullOK(_Symbol, InpMTF_MinScore)) return;

   double roc10 = GetROC(InpROC_Period, 1);   // ROC de 10 barras
   double roc5  = GetROC(InpROC_Fast_Period, 1); // ROC de 5 barras (confirmacion rapida)
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   // Condicion de alta volatilidad: ATR expandido
   bool highVol   = (avgATR <= 0 || atr >= avgATR * InpATR_VolMult);
   // Momentum alcista fuerte en ambas escalas de tiempo
   bool rocBull   = (roc10 >= InpROC_Threshold) && (roc5 > 0);
   // Tendencia M5 alcista
   bool uptrend   = (ema21 > ema50);
   // RSI en zona saludable
   bool rsiOK     = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);

   if (highVol && rocBull && uptrend && rsiOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Vol_ROC_Bull"))
         Print("COMPRA ROC Momentum | roc10=", roc10, "% | roc5=", roc5, "% | atr_mult=", atr/avgATR);
   }
}
