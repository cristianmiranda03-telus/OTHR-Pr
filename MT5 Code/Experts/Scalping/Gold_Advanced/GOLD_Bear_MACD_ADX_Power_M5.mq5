//+------------------------------------------------------------------+
//| GOLD_Bear_MACD_ADX_Power_M5.mq5                                  |
//| Strategy  : MACD + ADX BAJISTA — version potenciada              |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: London + NY       |
//| Magic     : 120004                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  Identico en logica al Bull pero para el lado bajista.           |
//|  El ADX > 28 con -DI > +DI confirma que la tendencia bajista    |
//|  es genuina y no un rebote tecnico.                              |
//|  Complementario de GOLD_Bull_MACD_ADX_Power: mientras el Bull   |
//|  opera en la tendencia principal alcista, el Bear opera las      |
//|  correcciones bajistas validadas por fuerza de tendencia.        |
//|                                                                  |
//| CONDICIONES DE ENTRADA:                                          |
//|  1. MACD(8,21,5): histograma cruza de positivo a negativo        |
//|  2. ADX(14) > 28                                                 |
//|  3. -DI > +DI — la direccion negativa domina (confirma bear)     |
//|  4. EMA21 < EMA50 — estructura bajista                           |
//|  5. ATR > 1.1x promedio                                          |
//|  6. RSI entre 28-50 — momentum bajista sin sobreventa extrema   |
//|                                                                  |
//| SL: 1.0 ATR sobre entrada                                        |
//| TP: 2.5 ATR                                                      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Bear MACD + ADX Power Filter | M5 | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== MACD Configuracion ==="
input int    InpMACD_Fast        = 8;
input int    InpMACD_Slow        = 21;
input int    InpMACD_Signal      = 5;

input group "=== ADX Filtro ==="
input int    InpADX_Period       = 14;
input double InpADX_Min          = 28.0;

input group "=== Filtros Adicionales ==="
input int    InpEMA_Fast         = 21;
input int    InpEMA_Slow         = 50;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 28.0;
input double InpRSI_Max          = 50.0;
input double InpATR_MinMult      = 1.1;
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
input int    InpMagic            = 120004;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

void GetADX_Full(double &adxVal, double &plusDI, double &minusDI, int shift = 1)
{
   adxVal = plusDI = minusDI = 0;
   double adxBuf[], plusBuf[], minusBuf[];
   ArraySetAsSeries(adxBuf, true); ArraySetAsSeries(plusBuf, true); ArraySetAsSeries(minusBuf, true);
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
   Print("GOLD_Bear_MACD_ADX_Power_M5 iniciado | ADX min=", InpADX_Min, " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double hist1 = macd1 - sig1;
   double hist2 = macd2 - sig2;

   double adx, plusDI, minusDI;
   GetADX_Full(adx, plusDI, minusDI, 1);

   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   bool macdCross   = (hist1 < 0 && hist2 >= 0);
   bool adxStrong   = (adx >= InpADX_Min);
   bool diAligned   = (minusDI > plusDI);
   bool downtrend   = (ema21 < ema50);
   bool rsiOK       = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);
   bool volActive   = (avgATR <= 0 || atr >= avgATR * InpATR_MinMult);

   if (macdCross && adxStrong && diAligned && downtrend && rsiOK && volActive)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_MACD_ADX_Bear"))
         Print("VENTA MACD+ADX | adx=", adx, " | -DI=", minusDI, " | rsi=", rsi);
   }
}
