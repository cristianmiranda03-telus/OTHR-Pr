//+------------------------------------------------------------------+
//| BTC_WE_Bear_Overbought_Snap.mq5                                  |
//| Strategy  : RSI Overbought Snap-Back BAJISTA                     |
//| Asset     : BTCUSD | Timeframe: M5 | Session: Weekend 24h        |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  Complementario de BTC_WE_Bull_Oversold_Snap.                   |
//|  BTC puede hacer "fake pumps" en fines de semana por manipulacion|
//|  de ballenas en baja liquidez. El RSI en M5 llega a extremos     |
//|  sobre 80 y luego colapsa rapidamente.                           |
//|  1. RSI sube sobre 80 (extremo overbought)                      |
//|  2. Siguiente barra: RSI cae bajo 75 (snap-back bajista)         |
//|  3. Vela de confirmacion bajista y cierra bajo EMA21             |
//|  4. ATR expandido (movimiento volatil activo)                    |
//|                                                                  |
//| Magic: 210007                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend RSI Overbought Snap Bear - M5 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== RSI Snap-Back Configuracion ==="
input int    InpRSI_Period       = 14;
input double InpRSI_Extreme      = 80.0;
input double InpRSI_Entry        = 75.0;
input int    InpEMA_Period       = 21;
input double InpATR_Expansion    = 1.3;
input int    InpATR_SMA_Bars     = 20;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.0;
input double InpTP_ATR_Mult      = 1.5;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.15;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210007;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
bool     g_rsiExtreme = false;

bool IsWeekend()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
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

   if (rsi1 > InpRSI_Extreme) g_rsiExtreme = true;
   if (rsi1 < 50) g_rsiExtreme = false;

   bool snapDown   = g_rsiExtreme && (rsi1 <= InpRSI_Entry) && (rsi2 > InpRSI_Entry);
   bool bearCandle = (close < open) && (close < ema21);
   bool volExpand  = (avgATR <= 0 || atr >= avgATR * InpATR_Expansion);

   if (snapDown && bearCandle && volExpand)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_Snap_Bear"))
      {
         g_rsiExtreme = false;
         Print("VENTA Snap-Back Bajista | rsi=", rsi1);
      }
   }
}
