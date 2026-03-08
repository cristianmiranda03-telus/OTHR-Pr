//+------------------------------------------------------------------+
//| BTC_WE_Bull_Morning_Breakout.mq5                                 |
//| Strategy  : Morning Breakout ALCISTA en fin de semana            |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend mañana    |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  En UTC-6, la "mañana" de fin de semana (8:00-11:00 local =      |
//|  14:00-17:00 UTC) tiende a ser el periodo con mayor actividad    |
//|  dado que coincide con el despertar del mercado crypto global.   |
//|  Estrategia:                                                     |
//|  1. Calcular el rango de las 4 horas previas (06:00-10:00 local) |
//|  2. Al llegar a las 10:00 local (16:00 UTC), si precio rompe     |
//|     el maximo de ese rango con una vela M15 alcista fuerte       |
//|  3. Confirmar con RSI > 55 y EMA8 > EMA21                       |
//|  4. Entrada al mercado con SL bajo el minimo del rango           |
//|                                                                  |
//| Magic: 210004                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend Morning Breakout Bull - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== Morning Breakout Configuracion ==="
input int    InpRangeBars        = 16;    // M15 bars del rango previo (16 x 15min = 4h)
input int    InpEntryWindowMin   = 120;   // Ventana de entrada en minutos (2h)
input double InpMinCandleStr     = 0.6;   // Fuerza minima de vela (close-open / ATR)

input group "=== Filtros ==="
input int    InpEMA_Fast         = 8;
input int    InpEMA_Slow         = 21;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 55.0;
input int    InpATR_Period       = 14;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.3;
input double InpTP_RR            = 2.5;   // Ratio riesgo/recompensa
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.2;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;    // UTC-6 -> La manana local es 14:00-17:00 UTC
input int    InpMorningStartUTC  = 14;    // Hora UTC de inicio de la manana local
input int    InpMagic            = 210004;

CTrade   g_trade;
datetime g_lastBarM15 = 0;
double   g_rangeHigh  = 0;
bool     g_entryDone  = false;

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

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour; int m = dt.min;
   int minOfDay = h * 60 + m;

   // Acumular rango 2h antes del inicio de manana
   int preStart = (InpMorningStartUTC - 2 + 24) % 24;
   if (h == preStart && m == 0)
   {
      g_rangeHigh  = 0;
      g_entryDone  = false;
   }
   if (h >= preStart && h < InpMorningStartUTC)
   {
      double hh = SC_GetHighestHigh(_Symbol, PERIOD_M15, InpRangeBars, 1);
      if (hh > g_rangeHigh) g_rangeHigh = hh;
      return;
   }

   // Ventana de entrada en la manana
   if (minOfDay < InpMorningStartUTC * 60 ||
       minOfDay > InpMorningStartUTC * 60 + InpEntryWindowMin) return;
   if (g_rangeHigh <= 0 || g_entryDone || SC_TotalPositions(InpMagic) > 0) return;

   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double open  = SC_Open(_Symbol, PERIOD_M15, 1);
   double ema8  = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Fast, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Slow, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M15, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0) return;

   double candleStr = (atr > 0) ? (close - open) / atr : 0;
   bool breakout  = (close > g_rangeHigh);
   bool emaOK     = (ema8 > ema21);
   bool rsiOK     = (rsi >= InpRSI_Min);
   bool strongBar = (candleStr >= InpMinCandleStr);

   if (breakout && emaOK && rsiOK && strongBar)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double slD   = ask - sl;
      double tp    = NormalizeDouble(ask + slD * InpTP_RR, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_Morning_Bull"))
      {
         g_entryDone = true;
         Print("COMPRA Morning Breakout | rangeHigh=", g_rangeHigh, " | close=", close);
      }
   }
}
