//+------------------------------------------------------------------+
//| GOLD_Bear_Acceleration_M5.mq5                                    |
//| Strategy  : Aceleracion de momentum bajista (2da oleada caida)   |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: London + NY       |
//| Magic     : 120002                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO — Por que funciona en el contexto actual del Oro:       |
//|  Las caidas del Oro en 2026 (post-noticias Fed, CPI, geopolítica) |
//|  tienen una estructura de 2 fases:                               |
//|  - Fase 1: caida inicial (el Bear ATR Expansion la captura)      |
//|  - Fase 2: aceleracion — los stops de compras largas se activan, |
//|            generando un segundo impulso igual o mas fuerte.      |
//|  Esta estrategia detecta cuando el momentum bajista ACELERA:     |
//|  velocidad de caida (ROC) + volumen anormal + MACD ya negativo.  |
//|                                                                  |
//| CONDICIONES DE ENTRADA:                                          |
//|  1. MACD(8,21,5) histograma NEGATIVO (momentum bajista activo)   |
//|  2. ROC(5) < -InpROC_Thresh (precio cayendo RAPIDO)              |
//|  3. Volumen barra actual > 1.5x promedio (presion vendedora)     |
//|  4. EMA21 < EMA50 (estructura bajista macro en M5)               |
//|  5. Barra actual es bajista con cuerpo > 0.6 ATR (vela fuerte)  |
//|                                                                  |
//| SL: sobre el maximo Donchian de 5 barras + 0.3 ATR              |
//| TP: 3x ATR (las aceleraciones recorren distancias largas)        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Bear Momentum Acceleration | M5 | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Parametros de Aceleracion ==="
input int    InpMACD_Fast        = 8;
input int    InpMACD_Slow        = 21;
input int    InpMACD_Signal      = 5;
input int    InpROC_Period       = 5;     // ROC rapido para medir velocidad
input double InpROC_Thresh       = 0.12;  // ROC < -0.12% = caida rapida en M5
input double InpVolMult          = 1.5;   // Volumen > N x promedio
input int    InpVolAvgBars       = 20;
input double InpMinBodyATR       = 0.6;   // Cuerpo bajista minimo en ATRs

input group "=== Filtros de Tendencia ==="
input int    InpEMA_Fast         = 21;
input int    InpEMA_Slow         = 50;
input int    InpDonchian_SL      = 5;    // Barras para SL dinamico (Donchian corto)

input group "=== Gestion de Riesgo ==="
input int    InpATR_Period       = 14;
input double InpRiskPct          = 0.5;
input double InpSL_Buffer        = 0.3;  // Buffer sobre Donchian high para SL
input double InpTP_ATR_Mult      = 3.0;  // TP amplio — segunda oleada es fuerte
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 65;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 120002;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

// ROC porcentual
double GetROC(int period, int shift = 1)
{
   double c = SC_Close(_Symbol, PERIOD_M5, shift);
   double p = SC_Close(_Symbol, PERIOD_M5, shift + period);
   return (p > 0) ? ((c - p) / p) * 100.0 : 0;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_Bear_Acceleration_M5 iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // MACD histograma
   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   double hist1 = macd1 - sig1;

   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open   = SC_Open(_Symbol,  PERIOD_M5, 1);
   double roc    = GetROC(InpROC_Period, 1);
   double vol    = (double)SC_Volume(_Symbol, PERIOD_M5, 1);
   double avgVol = SC_AvgVolume(_Symbol, PERIOD_M5, InpVolAvgBars, 2);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double donH   = SC_GetHighestHigh(_Symbol, PERIOD_M5, InpDonchian_SL, 2);
   if (atr <= 0) return;

   double body     = open - close; // positivo si bajista

   // Condiciones de aceleracion bajista
   bool macdBear  = (hist1 < 0);
   bool fastDrop  = (roc <= -InpROC_Thresh);
   bool volSpike  = (avgVol <= 0 || vol >= avgVol * InpVolMult);
   bool downtrend = (ema21 < ema50);
   bool bigBear   = (body >= atr * InpMinBodyATR);

   if (macdBear && fastDrop && volSpike && downtrend && bigBear)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(donH + atr * InpSL_Buffer, digits);
      double slD   = sl - bid;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Bear_Accel"))
         Print("VENTA Aceleracion | roc=", roc, "% | vol/avg=", vol/avgVol, " | body=", body);
   }
}
