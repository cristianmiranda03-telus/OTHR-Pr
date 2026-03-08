//+------------------------------------------------------------------+
//| BTC_WE_Bear_BB_Squeeze.mq5                                       |
//| Strategy  : Bollinger Band Squeeze BEARISH Breakdown             |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend 24h       |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  Identico al Bull pero en direccion bajista. Cuando las bandas   |
//|  de Bollinger se expanden despues de un squeeze y el precio       |
//|  rompe hacia abajo (cierra bajo la banda media + bajo EMA21)     |
//|  con CCI negativo = venta.                                       |
//|  Complementario de BTC_WE_Bull_BB_Squeeze.                      |
//|                                                                  |
//| Magic: 210002                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend Squeeze Bear - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== Bollinger Band Squeeze ==="
input int    InpBB_Period        = 20;
input double InpBB_Dev           = 2.0;
input int    InpSqueeze_Lookback = 30;
input double InpExpansion_Pct    = 0.05;

input group "=== Filtros de Confirmacion ==="
input int    InpEMA_Period       = 21;
input int    InpCCI_Period       = 14;
input int    InpATR_Period       = 14;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.5;
input double InpTP_ATR_Mult      = 3.0;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.2;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210002;

CTrade   g_trade;
datetime g_lastBarM15 = 0;

double GetBBWidth(int shift)
{
   double u, m, l;
   SC_GetBB(_Symbol, PERIOD_M15, InpBB_Period, InpBB_Dev, shift, u, m, l);
   return (u > 0) ? (u - l) : 0;
}

bool IsSqueeze(int shift = 1)
{
   double cw = GetBBWidth(shift);
   if (cw <= 0) return false;
   for (int i = shift + 1; i <= shift + InpSqueeze_Lookback; i++)
      if (GetBBWidth(i) <= cw) return false;
   return true;
}

bool IsExpanding()
{
   double w1 = GetBBWidth(1), w2 = GetBBWidth(2);
   if (w1 <= 0 || w2 <= 0) return false;
   return (w1 > w2 * (1.0 + InpExpansion_Pct));
}

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
   Print("BTC_WE_Bear_BB_Squeeze iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double upper, mid, lower;
   SC_GetBB(_Symbol, PERIOD_M15, InpBB_Period, InpBB_Dev, 1, upper, mid, lower);
   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 1);
   double cci   = SC_GetCCI(_Symbol, PERIOD_M15, InpCCI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0 || upper <= 0) return;

   bool squeezeWas = IsSqueeze(2);
   bool nowExpand  = IsExpanding();
   bool bearDir    = (close < mid) && (close < ema21); // direccion bajista
   bool cciOK      = (cci < 0);

   if (squeezeWas && nowExpand && bearDir && cciOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_Squeeze_Bear"))
         Print("Entrada VENTA | lots=", lots, " | BB Squeeze expansion bajista");
   }
}
