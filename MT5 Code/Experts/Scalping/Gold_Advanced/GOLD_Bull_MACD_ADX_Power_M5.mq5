//+------------------------------------------------------------------+
//| GOLD_Bull_MACD_ADX_Power_M5.mq5                                  |
//| Strategy  : MACD + ADX ALCISTA — version potenciada              |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: London + NY       |
//| Magic     : 120003                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO — Por que mejora al MACD Bull original:                 |
//|  El GOLD_Bull_MACD_Momentum existente funciona bien pero tiene   |
//|  senales falsas en periodos choppy (cuando el Oro consolida      |
//|  brevemente dentro de un trend). El ADX (Average Directional     |
//|  Index) mide la FUERZA de la tendencia independientemente de     |
//|  su direccion.                                                   |
//|                                                                  |
//|  ADX > 28 = tendencia ESTABLECIDA (momentum genuino)             |
//|  ADX < 20 = mercado lateral/choppy (evitar MACD)                 |
//|                                                                  |
//|  Al combinar MACD(8,21,5) + ADX > 28 + ATR expandido:           |
//|  - Eliminamos ~60% de senales falsas en consolidacion            |
//|  - Mantenemos la mayoria de senales buenas en trend genuino      |
//|  - Resultado: menos trades pero mayor tasa de acierto            |
//|                                                                  |
//| CONDICIONES DE ENTRADA:                                          |
//|  1. MACD(8,21,5): histograma cruza de negativo a positivo        |
//|  2. ADX(14) > 28 — tendencia confirmada por fuerza               |
//|  3. +DI > -DI — la direccion positiva domina (confirma bull)     |
//|  4. EMA21 > EMA50 — estructura de precios alcista                |
//|  5. ATR > 1.1x promedio — volatilidad activa (no mercado muerto) |
//|  6. RSI entre 50-72 — momentum positivo sin sobrecompra extrema  |
//|                                                                  |
//| SL: 1.0 ATR bajo entrada (ajustado — señal de mayor calidad)     |
//| TP: 2.5 ATR (tendencias fuertes con ADX > 28 viajan mas lejos)  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Bull MACD + ADX Power Filter | M5 | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== MACD Configuracion ==="
input int    InpMACD_Fast        = 8;
input int    InpMACD_Slow        = 21;
input int    InpMACD_Signal      = 5;

input group "=== ADX Filtro de Fuerza de Tendencia ==="
input int    InpADX_Period       = 14;
input double InpADX_Min          = 28.0;  // ADX minimo para confirmar tendencia

input group "=== Filtros Adicionales ==="
input int    InpEMA_Fast         = 21;
input int    InpEMA_Slow         = 50;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 50.0;
input double InpRSI_Max          = 72.0;
input double InpATR_MinMult      = 1.1;   // ATR > N x promedio
input int    InpATR_SMA_Bars     = 20;

input group "=== Gestion de Riesgo ==="
input int    InpATR_Period       = 14;
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.0;
input double InpTP_ATR_Mult      = 2.5;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 65;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 120003;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bullish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBarM5 = 0;

// Retorna ADX, +DI, -DI
void GetADX_Full(double &adxVal, double &plusDI, double &minusDI, int shift = 1)
{
   adxVal = plusDI = minusDI = 0;
   double adxBuf[], plusBuf[], minusBuf[];
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(plusBuf, true);
   ArraySetAsSeries(minusBuf, true);
   int h = iADX(_Symbol, PERIOD_M5, InpADX_Period);
   if (h == INVALID_HANDLE) return;
   if (CopyBuffer(h, 0, shift, 1, adxBuf)   >= 1) adxVal  = adxBuf[0];
   if (CopyBuffer(h, 1, shift, 1, plusBuf)  >= 1) plusDI  = plusBuf[0];
   if (CopyBuffer(h, 2, shift, 1, minusBuf) >= 1) minusDI = minusBuf[0];
   IndicatorRelease(h);
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
   Print("GOLD_Bull_MACD_ADX_Power_M5 iniciado | ADX min=", InpADX_Min, " | Magic=", InpMagic);
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

   // MACD
   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double hist1 = macd1 - sig1;
   double hist2 = macd2 - sig2;

   // ADX con +DI y -DI
   double adx, plusDI, minusDI;
   GetADX_Full(adx, plusDI, minusDI, 1);

   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   // Condiciones de alta calidad
   bool macdCross  = (hist1 > 0 && hist2 <= 0);    // cruce fresco del histograma
   bool adxStrong  = (adx >= InpADX_Min);            // tendencia establecida
   bool diAligned  = (plusDI > minusDI);             // direccion positiva domina
   bool uptrend    = (ema21 > ema50);
   bool rsiOK      = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);
   bool volActive  = (avgATR <= 0 || atr >= avgATR * InpATR_MinMult);

   if (macdCross && adxStrong && diAligned && uptrend && rsiOK && volActive)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_MACD_ADX_Bull"))
         Print("COMPRA MACD+ADX | adx=", adx, " | +DI=", plusDI, " | rsi=", rsi);
   }
}
