//+------------------------------------------------------------------+
//| BTC_WE_Bear_EMA_Breakdown.mq5                                    |
//| Strategy  : EMA50 Breakdown BAJISTA con confirmacion             |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend 24h       |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  Complementario de BTC_WE_Bull_EMA_Reclaim.                     |
//|  Cuando BTC estaba sobre EMA50 y rompe hacia abajo con una vela  |
//|  bajista fuerte y volumen sobre promedio = señal de continuacion  |
//|  bajista. Es la confirmacion de que la EMA50 se perdio como      |
//|  soporte y ahora puede actuar como resistencia.                  |
//|  Condiciones:                                                    |
//|  1. Barra anterior cerro SOBRE la EMA50                         |
//|  2. Barra actual cierra BAJO la EMA50 (breakdown)               |
//|  3. La barra es bajista con cuerpo > 0.5 ATR                    |
//|  4. RSI entre 35-60 (evita sobreventa ya existente)             |
//|                                                                  |
//| Magic: 210010                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend EMA50 Breakdown Bear - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== EMA Breakdown Configuracion ==="
input int    InpEMA_Period       = 50;
input double InpMinBodyATR       = 0.5;
input double InpVolMult          = 1.1;
input int    InpVolAvgBars       = 15;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 35.0;  // RSI min (no sobrevendido ya)
input double InpRSI_Max          = 60.0;  // RSI max para venta

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
input int    InpMagic            = 210010;

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

   double ema50_1 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 1);
   double ema50_2 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 2);
   double close1  = SC_Close(_Symbol, PERIOD_M15, 1);
   double close2  = SC_Close(_Symbol, PERIOD_M15, 2);
   double open1   = SC_Open(_Symbol, PERIOD_M15, 1);
   double rsi     = SC_GetRSI(_Symbol, PERIOD_M15, InpRSI_Period, 1);
   double atr     = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   double vol1    = (double)SC_Volume(_Symbol, PERIOD_M15, 1);
   double avgVol  = SC_AvgVolume(_Symbol, PERIOD_M15, InpVolAvgBars, 2);
   if (atr <= 0) return;

   double body    = open1 - close1; // positivo = bajista

   bool prevAbove = (close2 > ema50_2);
   bool nowBelow  = (close1 < ema50_1);
   bool strongBar = (body >= atr * InpMinBodyATR);
   bool volOK     = (avgVol <= 0 || vol1 >= avgVol * InpVolMult);
   bool rsiOK     = (rsi >= InpRSI_Min && rsi <= InpRSI_Max);

   if (prevAbove && nowBelow && strongBar && volOK && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_EMA_Breakdown"))
         Print("VENTA EMA Breakdown | ema50=", ema50_1, " | close=", close1, " | rsi=", rsi);
   }
}
