//+------------------------------------------------------------------+
//| BTC_WE_Range_VWAP_Reversion.mq5                                  |
//| Strategy  : VWAP Intraday Reversion - RANGO (ambas direcciones)  |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend 24h       |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  El VWAP (Volume Weighted Average Price) actua como imán de      |
//|  precio en mercados sin tendencia. Esta estrategia aproxima el   |
//|  VWAP diario con una SMA de precio tipico (H+L+C)/3 ponderada   |
//|  por volumen acumulado intradiario.                              |
//|  Cuando el precio se aleja del VWAP mas de 1.5 ATR:             |
//|  - Muy por debajo: comprar al primer signo de recuperacion        |
//|  - Muy por arriba: vender al primer signo de debilidad           |
//|  Filtro: RSI diverge del precio (no confirma el extremo)         |
//|  Rota entre compras y ventas segun donde este el precio vs VWAP. |
//|                                                                  |
//| Magic: 210008                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend VWAP Reversion Range - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== VWAP Reversion Configuracion ==="
input int    InpVWAP_Period      = 24;    // M15 bars = 6h de VWAP aproximado
input double InpDev_ATR          = 1.5;   // Desviacion minima del VWAP en ATRs
input int    InpRSI_Period       = 7;     // RSI rapido para confirmar momentum
input double InpRSI_BuyMax       = 45.0;  // RSI max para compra (precio bajo pero RSI no confirma caida)
input double InpRSI_SellMin      = 55.0;  // RSI min para venta (precio alto pero RSI no confirma subida)

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.4;
input double InpSL_ATR_Mult      = 1.2;
input double InpTP_ATR_Mult      = 1.8;  // TP hacia VWAP
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.1;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210008;

CTrade   g_trade;
datetime g_lastBarM15 = 0;

bool IsWeekend()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

// VWAP aproximado: SMA del precio tipico en M15
double GetApproxVWAP(int period)
{
   double sum = 0;
   int    cnt = 0;
   for (int i = 1; i <= period; i++)
   {
      double h = SC_High(_Symbol, PERIOD_M15, i);
      double l = SC_Low(_Symbol, PERIOD_M15, i);
      double c = SC_Close(_Symbol, PERIOD_M15, i);
      if (h <= 0) continue;
      sum += (h + l + c) / 3.0;
      cnt++;
   }
   return (cnt > 0) ? sum / cnt : 0;
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

   double vwap  = GetApproxVWAP(InpVWAP_Period);
   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M15, InpRSI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0 || vwap <= 0) return;

   double deviation = close - vwap;
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // COMPRA: precio muy por debajo del VWAP y RSI no esta colapsando
   if (deviation < -atr * InpDev_ATR && rsi < InpRSI_BuyMax)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(vwap, digits); // TP al VWAP
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_VWAP_BUY"))
         Print("COMPRA VWAP Rev | desv=", deviation, " | rsi=", rsi, " | vwap=", vwap);
   }
   // VENTA: precio muy por arriba del VWAP y RSI no confirma subida
   else if (deviation > atr * InpDev_ATR && rsi > InpRSI_SellMin)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(vwap, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_VWAP_SELL"))
         Print("VENTA VWAP Rev | desv=", deviation, " | rsi=", rsi, " | vwap=", vwap);
   }
}
