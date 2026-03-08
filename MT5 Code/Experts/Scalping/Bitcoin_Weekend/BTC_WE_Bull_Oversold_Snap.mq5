//+------------------------------------------------------------------+
//| BTC_WE_Bull_Oversold_Snap.mq5                                    |
//| Strategy  : RSI Oversold Snap-Back ALCISTA                       |
//| Asset     : BTCUSD | Timeframe: M5 | Session: Weekend 24h        |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  En fines de semana con baja liquidez, BTC puede caer bruscamente|
//|  y luego rebotar igual de rapido (snap-back). Esta estrategia    |
//|  captura esos rebotes extremos:                                  |
//|  1. RSI cae bajo 20 (extremo oversold en M5 - muy raro)          |
//|  2. En la siguiente barra, RSI cruza de vuelta sobre 25           |
//|  3. La vela de confirmacion es alcista y cierra sobre EMA21      |
//|  4. El ATR esta expandido (movimiento volatil activo)            |
//|  El TP es modesto (1.5x SL) para capturar el snap rapido.       |
//|  Complementario de BTC_WE_Bear_Reversal_Fade.                   |
//|                                                                  |
//| Magic: 210006                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend RSI Oversold Snap Bull - M5 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== RSI Snap-Back Configuracion ==="
input int    InpRSI_Period       = 14;
input double InpRSI_Extreme      = 20.0;  // Nivel extremo oversold (muy bajo para M5)
input double InpRSI_Entry        = 25.0;  // Nivel de cross-back para entrada
input int    InpEMA_Period       = 21;
input double InpATR_Expansion    = 1.3;   // ATR debe ser > N x promedio ATR (volatilidad)
input int    InpATR_SMA_Bars     = 20;    // Barras para promedio ATR

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.0;
input double InpTP_ATR_Mult      = 1.5;  // TP conservador para snap
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.15;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210006;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
bool     g_rsiExtreme = false; // RSI estuvo en extremo

bool IsWeekend()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

// ATR promedio de los ultimos N barras
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
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double rsi1  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double open  = SC_Open(_Symbol, PERIOD_M5, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   // Actualizar flag de extremo
   if (rsi1 < InpRSI_Extreme) g_rsiExtreme = true;
   if (rsi1 > 50) g_rsiExtreme = false; // resetear al normalizarse

   bool snapBack  = g_rsiExtreme && (rsi1 >= InpRSI_Entry) && (rsi2 < InpRSI_Entry);
   bool bullCandle = (close > open) && (close > ema21);
   bool volExpand = (avgATR <= 0 || atr >= avgATR * InpATR_Expansion);

   if (snapBack && bullCandle && volExpand)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_Snap_Bull"))
      {
         g_rsiExtreme = false;
         Print("COMPRA Snap-Back | rsi=", rsi1, " | atr expansion=", atr/avgATR);
      }
   }
}
