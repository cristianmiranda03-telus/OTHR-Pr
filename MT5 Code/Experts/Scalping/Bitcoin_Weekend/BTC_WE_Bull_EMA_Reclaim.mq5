//+------------------------------------------------------------------+
//| BTC_WE_Bull_EMA_Reclaim.mq5                                      |
//| Strategy  : EMA50 Reclaim ALCISTA con confirmacion de volumen    |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend 24h       |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  La EMA50 en M15 actua como nivel de soporte/resistencia         |
//|  psicologico importante. Cuando BTC cae bajo la EMA50 y luego    |
//|  "reclama" el nivel (cierra de nuevo sobre ella) con una vela    |
//|  fuerte = señal de continuation alcista.                         |
//|  Condiciones:                                                    |
//|  1. La barra anterior cerro BAJO la EMA50                        |
//|  2. La barra actual cierra SOBRE la EMA50 (reclaim)              |
//|  3. La barra de reclaim es alcista y tiene cuerpo > 0.5 ATR      |
//|  4. Volumen de la barra de reclaim > promedio (confirmation)      |
//|  5. RSI entre 40-65 (evita sobrecompra ya existente)             |
//|                                                                  |
//| Magic: 210009                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend EMA50 Reclaim Bull - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== EMA Reclaim Configuracion ==="
input int    InpEMA_Period       = 50;    // EMA a reclamar
input double InpMinBodyATR       = 0.5;   // Cuerpo minimo de vela en ATRs
input double InpVolMult          = 1.1;   // Volumen minimo vs promedio
input int    InpVolAvgBars       = 15;    // Barras para promedio de volumen
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 40.0;  // RSI min para compra
input double InpRSI_Max          = 65.0;  // RSI max para compra (no sobrecomprado)

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.5;
input double InpTP_ATR_Mult      = 2.5;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.2;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210009;

CTrade   g_trade;
datetime g_lastBarM15 = 0;

bool IsWeekend()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema50_1 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 1); // EMA en barra actual
   double ema50_2 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 2); // EMA en barra anterior
   double close1  = SC_Close(_Symbol, PERIOD_M15, 1); // cierre barra actual
   double close2  = SC_Close(_Symbol, PERIOD_M15, 2); // cierre barra anterior
   double open1   = SC_Open(_Symbol, PERIOD_M15, 1);
   double rsi     = SC_GetRSI(_Symbol, PERIOD_M15, InpRSI_Period, 1);
   double atr     = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   double vol1    = (double)SC_Volume(_Symbol, PERIOD_M15, 1);
   double avgVol  = SC_AvgVolume(_Symbol, PERIOD_M15, InpVolAvgBars, 2);
   if (atr <= 0) return;

   double body    = close1 - open1; // positivo = alcista

   // Condicion: la barra anterior cerro bajo EMA50 y la actual la reclama
   bool prevBelow = (close2 < ema50_2);
   bool nowAbove  = (close1 > ema50_1);
   bool strongBar = (body >= atr * InpMinBodyATR);
   bool volOK     = (avgVol <= 0 || vol1 >= avgVol * InpVolMult);
   bool rsiOK     = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);

   if (prevBelow && nowAbove && strongBar && volOK && rsiOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_EMA_Reclaim"))
         Print("COMPRA EMA Reclaim | ema50=", ema50_1, " | close=", close1, " | rsi=", rsi);
   }
}
