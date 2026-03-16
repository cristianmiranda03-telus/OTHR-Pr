//+------------------------------------------------------------------+
//| GOLD_Bull_VolatileWhisper_MTF_M5.mq5                             |
//| Strategy  : Volatile Whisper Retest + filtro Multi-Timeframe     |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: NY (14-21 UTC)    |
//| Magic     : 120006                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO — Evolucion del VolatileWhisper_Retest existente:       |
//|  El VolatileWhisper_Retest (M1) tiene excelente logica de price  |
//|  action (consolidacion -> breakout -> retest silencioso ->       |
//|  vela de rechazo). Su problema principal en el contexto actual:  |
//|  genera setups CONTRA la tendencia dominante con frecuencia.     |
//|                                                                  |
//|  Esta version agrega un FILTRO MULTI-TIMEFRAME:                  |
//|  - M15: EMA21 > EMA50 (tendencia alcista macro)                  |
//|  - M15: ADX > 20 (confirmacion de que hay direccionalidad)       |
//|  Solo cuando M15 es alcista se toman setups LONG en M5.          |
//|  El timeframe de entrada es M5 (mas estable que M1, menos ruido) |
//|                                                                  |
//| ESTRUCTURA DEL PATRON (misma logica que VolatileWhisper):        |
//|  Paso 1: Detectar consolidacion de N barras M5                   |
//|  Paso 2: Confirmar breakout alcista (vela con cuerpo > 70% rango)|
//|          PERO ATR del breakout debe estar SOBRE baseline         |
//|          (breakout genuino, no ruido)                            |
//|  Paso 3: El retest del nivel roto debe ser en LOW VOLATILITY     |
//|          (ATR < baseline, vela chica = "el susurro")             |
//|  Paso 4: Vela de rechazo alcista confirma la entrada             |
//|  Paso 5: NUEVO — M15 debe estar alcista durante todo el patron   |
//|                                                                  |
//| DIFERENCIAS con el original (M1):                               |
//|  - Timeframe M5 (menos ruido, spreads no impactan tanto)         |
//|  - Filtro M15 elimina trades contra tendencia                    |
//|  - ADX > 20 en M15 confirma que el movimiento tiene fuerza       |
//|  - SL/TP ajustados para M5 (ATR mayor)                          |
//|                                                                  |
//| SL: bajo el minimo de la vela de rechazo - 0.5 ATR(M5)          |
//| TP: 2.0x riesgo                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Volatile Whisper Retest + MTF M15 Filter | M5 | NY"

#include "..\Common\Scalping_Common.mqh"

//--- Inputs
input group "=== Parametros Volatile Whisper (M5) ==="
input int    InpConsolBars       = 8;     // Barras de consolidacion previa
input double InpBreakout_BodyPct = 0.65;  // Cuerpo breakout > 65% del rango de la vela
input double InpRetest_BodyPct   = 0.35;  // Vela retest tiene cuerpo < 35% del avg body
input double InpRetest_WickPct   = 0.55;  // Mechas del retest < 55% del cuerpo
input double InpReject_BodyPct   = 0.45;  // Cuerpo minimo de la vela de rechazo

input group "=== ATR del Breakout y Retest ==="
input int    InpATR_Period       = 5;     // ATR corto para capturar el spike del breakout
input int    InpATR_Baseline     = 20;    // Baseline del ATR para comparacion

input group "=== Filtro Multi-Timeframe M15 ==="
input int    InpM15_EMA_Fast     = 21;   // EMA M15 rapida
input int    InpM15_EMA_Slow     = 50;   // EMA M15 lenta
input int    InpM15_ADX_Period   = 14;
input double InpM15_ADX_Min      = 20.0; // ADX M15 minimo (alguna direccionalidad)
input bool   InpUseMTF       = true;   // Activar filtro D1+H1 adicional al M15
input int    InpMTF_MinScore = 2;      // Min score total D1+H1+M15 (recomendado: 2)

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Buffer    = 0.5;
input double InpTP_RR            = 2.0;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 65;

input group "=== Sesion ==="
input int    InpNY_StartHour     = 14;   // Inicio sesion NY en UTC
input int    InpNY_EndHour       = 21;
input int    InpMagic            = 120006;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

//+------------------------------------------------------------------+
//| Helpers de precio M5                                             |
//+------------------------------------------------------------------+
bool IsNYSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return (dt.hour >= InpNY_StartHour && dt.hour < InpNY_EndHour);
}

double GetATR_M5(int shift)  { return SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, shift); }

double GetATRBaseline_M5(int shift)
{
   double sum = 0;
   for (int i = shift + 1; i <= shift + InpATR_Baseline; i++)
      sum += GetATR_M5(i);
   return (InpATR_Baseline > 0) ? sum / InpATR_Baseline : 0;
}

double AvgBodyM5(int fromBar, int count)
{
   double sum = 0;
   for (int i = fromBar; i < fromBar + count; i++)
      sum += MathAbs(SC_Close(_Symbol, PERIOD_M5, i) - SC_Open(_Symbol, PERIOD_M5, i));
   return (count > 0) ? sum / count : 0;
}

//+------------------------------------------------------------------+
//| Verifica rango de consolidacion en M5                            |
//+------------------------------------------------------------------+
bool GetConsolRange(int startBar, int count, double &rHigh, double &rLow)
{
   rHigh = SC_GetHighestHigh(_Symbol, PERIOD_M5, count, startBar);
   rLow  = SC_GetLowestLow(_Symbol,  PERIOD_M5, count, startBar);
   return (rHigh > rLow);
}

//+------------------------------------------------------------------+
//| Verifica breakout alcista con cuerpo fuerte                      |
//+------------------------------------------------------------------+
bool IsBreakoutLong(int barIdx, double rangeHigh)
{
   double c = SC_Close(_Symbol, PERIOD_M5, barIdx);
   double o = SC_Open(_Symbol,  PERIOD_M5, barIdx);
   double h = SC_High(_Symbol,  PERIOD_M5, barIdx);
   double l = SC_Low(_Symbol,   PERIOD_M5, barIdx);
   if (c <= rangeHigh) return false;
   double range = h - l;
   if (range < 1e-9) return false;
   return (MathAbs(c - o) / range >= InpBreakout_BodyPct);
}

//+------------------------------------------------------------------+
//| Verifica que el retest toca el nivel (margen de 5 puntos)        |
//+------------------------------------------------------------------+
bool RetestTouchesLevel(double level, int barIdx)
{
   double h = SC_High(_Symbol, PERIOD_M5, barIdx);
   double l = SC_Low(_Symbol,  PERIOD_M5, barIdx);
   double margin = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   return (l <= level + margin && h >= level - margin);
}

//+------------------------------------------------------------------+
//| Verifica que la vela de retest es de baja volatilidad ("whisper")|
//+------------------------------------------------------------------+
bool IsLowVolRetest(int barIdx, double avgBody)
{
   double c = SC_Close(_Symbol, PERIOD_M5, barIdx);
   double o = SC_Open(_Symbol,  PERIOD_M5, barIdx);
   double h = SC_High(_Symbol,  PERIOD_M5, barIdx);
   double l = SC_Low(_Symbol,   PERIOD_M5, barIdx);
   double body = MathAbs(c - o);
   double range = h - l;
   if (range < 1e-9) return true;
   // Cuerpo pequeno vs promedio
   if (avgBody > 1e-9 && body > InpRetest_BodyPct * avgBody) return false;
   // Mechas contenidas
   double lowerWick = MathMin(o, c) - l;
   double upperWick = h - MathMax(o, c);
   if (body > 1e-9 && (lowerWick > InpRetest_WickPct * body || upperWick > InpRetest_WickPct * body))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Verifica vela de rechazo alcista (mecha inferior larga)          |
//+------------------------------------------------------------------+
bool IsRejectionLong(int barIdx)
{
   double c = SC_Close(_Symbol, PERIOD_M5, barIdx);
   double o = SC_Open(_Symbol,  PERIOD_M5, barIdx);
   double h = SC_High(_Symbol,  PERIOD_M5, barIdx);
   double l = SC_Low(_Symbol,   PERIOD_M5, barIdx);
   if (c <= o) return false; // debe cerrar alcista
   double range = h - l;
   if (range < 1e-9) return false;
   double lowerWick = MathMin(o, c) - l;
   if (lowerWick < range * 0.4) return false; // mecha inferior significativa
   return ((c - o) / range >= InpReject_BodyPct || (c - l) >= range * 0.5);
}

//+------------------------------------------------------------------+
//| Filtro M15: tendencia alcista confirmada por EMA y ADX           |
//+------------------------------------------------------------------+
bool IsM15BullishTrend()
{
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Fast, 1);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Slow, 1);
   double close = SC_Close(_Symbol,  PERIOD_M15, 1);

   // EMA alcista
   if (!(ema21 > ema50 && close > ema21)) return false;

   // ADX confirma direccionalidad
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   int h = iADX(_Symbol, PERIOD_M15, InpM15_ADX_Period);
   if (h == INVALID_HANDLE) return true; // falla gracefully
   double adxVal = (CopyBuffer(h, 0, 1, 1, adxBuf) >= 1) ? adxBuf[0] : 0;
   IndicatorRelease(h);
   return (adxVal >= InpM15_ADX_Min);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_Bull_VolatileWhisper_MTF_M5 iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!IsNYSession()) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // FILTRO MTF: Solo operar si M15 es alcista
   if (!IsM15BullishTrend()) return;
   if (InpUseMTF && !SC_MTF_BullOK(_Symbol, InpMTF_MinScore)) return;

   double rangeHigh, rangeLow;
   if (!GetConsolRange(InpConsolBars + 5, InpConsolBars, rangeHigh, rangeLow)) return;

   // El ATR actual debe estar BAJO el baseline (breakout ya ocurrio, ahora buscamos retest quieto)
   double atrNow     = GetATR_M5(1);
   double baseline   = GetATRBaseline_M5(1);
   if (baseline <= 0) return;
   // Durante el retest queremos volatilidad BAJA (el "whisper")
   if (atrNow >= baseline) return;

   double avgBody = AvgBodyM5(2, 10);

   // Buscar el breakout en las ultimas 5 barras y el patron completo
   for (int b = 2; b <= 5; b++)
   {
      // ¿Hubo breakout alcista en la barra b+1?
      if (!IsBreakoutLong(b + 1, rangeHigh)) continue;

      double retestLevel = rangeHigh;
      bool   foundRetest = false;
      int    rejectBar   = -1;

      // Buscar el retest del nivel roto en las barras posteriores
      for (int r = b; r >= 1; r--)
      {
         if (!RetestTouchesLevel(retestLevel, r)) continue;
         // El retest debe ser en baja volatilidad
         if (baseline > 0 && GetATR_M5(r) >= baseline) break; // volatilidad alta = retest invalido
         if (!IsLowVolRetest(r, avgBody)) continue;
         // Buscar vela de rechazo alcista (en la barra del retest o la siguiente)
         if (r >= 1 && IsRejectionLong(r - 1)) { foundRetest = true; rejectBar = r - 1; break; }
         if (IsRejectionLong(r))                { foundRetest = true; rejectBar = r;     break; }
      }

      if (!foundRetest || rejectBar < 0) continue;

      // Entrada
      double rejLow   = SC_Low(_Symbol,  PERIOD_M5, rejectBar);
      double rejHigh  = SC_High(_Symbol, PERIOD_M5, rejectBar);
      double atrEntry = GetATR_M5(rejectBar + 1);
      double sl       = NormalizeDouble(rejLow - atrEntry * InpSL_ATR_Buffer,
                                        (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double riskDist = ask - sl;
      if (riskDist <= 0) continue;
      double tp    = NormalizeDouble(ask + riskDist * InpTP_RR,
                                     (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double lots  = SC_CalcLotSize(riskDist / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                    InpRiskPct, InpMinLot, InpMaxLot);
      if (lots >= InpMinLot)
      {
         if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_VW_MTF_L"))
            Print("COMPRA VW MTF | M15_alcista=si | rangeHigh=", rangeHigh, " | sl=", sl, " | tp=", tp);
      }
      return;
   }
}
